{ config, lib, pkgs, ... }:
let
  cfg = config.personal.tailnetServices;
  socket = "/run/tailnet-services/tailscaled.sock";
  ts = "tailscale --socket=${socket}";
  apps = lib.mapAttrsToList (name: app: app // { inherit name; }) cfg.services;
in {
  options.personal.tailnetServices = {
    phase = lib.mkOption {
      type = lib.types.enum [ "legacy" "prepare" "services" ];
      default = "legacy";
      description = "Prepare the shared host before handing application DNS names to Services.";
    };
    hostName = lib.mkOption {
      type = lib.types.str;
      default = "${config.networking.hostName}-services";
    };
    tag = lib.mkOption { type = lib.types.str; default = "tag:tycho-services"; };
    services = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          port = lib.mkOption { type = lib.types.port; };
          redirectPort = lib.mkOption { type = lib.types.port; };
          after = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; };
        };
      });
    };
  };

  config = lib.mkIf (cfg.phase != "legacy") {
    assertions = [ {
      assertion = lib.versionAtLeast pkgs.tailscale.version "1.94";
      message = "The shared Tailscale Services host requires Tailscale 1.94 or later.";
    } ];

    # A tagged userspace node publishes all applications. The ordinary machine
    # daemon, SSH identity, Rex mapping, and tsidp remain independent.
    systemd.services.tailnet-services = {
      description = "Shared Tailscale Services host";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "notify";
        ExecStart = "${pkgs.tailscale}/bin/tailscaled --tun=userspace-networking --statedir=/var/lib/tailnet-services --state=/var/lib/tailnet-services/tailscaled.state --socket=${socket} --port=0";
        StateDirectory = "tailnet-services";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "tailnet-services";
        RuntimeDirectoryMode = "0700";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    # The daemon persists Serve mappings. Clear only this dedicated daemon when
    # preparing (including a return from Services), so it cannot publish stale
    # routes alongside the restored legacy nodes.
    systemd.services.tailnet-services-prepare = lib.mkIf (cfg.phase == "prepare") {
      description = "Prepare an unpublished Tailscale Services host";
      wantedBy = [ "multi-user.target" ];
      requires = [ "tailnet-services.service" ];
      after = [ "tailnet-services.service" ];
      partOf = [ "tailnet-services.service" ];
      path = [ pkgs.tailscale pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "5s";
      };
      script = ''
        # Reset needs a logged-in network map. A brand-new, unenrolled daemon
        # has no mappings to clear and must not fail preparation.
        current=$(${ts} serve status --json)
        mappings=$(printf '%s' "$current" | jq 'length')
        if [ "$mappings" -gt 0 ]; then
          ${ts} serve reset
        fi
      '';
    };

    systemd.services.tailnet-services-publish = lib.mkIf (cfg.phase == "services") {
      description = "Publish applications as named Tailscale Services";
      wantedBy = [ "multi-user.target" ];
      requires = [ "tailnet-services.service" ];
      wants = [ "nginx.service" ] ++ lib.concatMap (app: app.after) apps;
      after = [ "tailnet-services.service" "nginx.service" ] ++ lib.concatMap (app: app.after) apps;
      partOf = [ "tailnet-services.service" ];
      path = [ pkgs.tailscale pkgs.jq pkgs.coreutils ];
      serviceConfig = { Type = "simple"; Restart = "on-failure"; RestartSec = "15s"; };
      script = ''
        # Enrollment is completed in the prepare phase. Fail closed if the
        # identity is not tagged; never repurpose the machine's daemon.
        ${ts} status --json | jq -e --arg tag ${lib.escapeShellArg cfg.tag} \
          '.BackendState == "Running" and ((.Self.Tags // []) | index($tag) != null)' >/dev/null
        ${ts} set --hostname=${lib.escapeShellArg cfg.hostName} \
          --accept-dns=false --accept-routes=false
        ${lib.concatMapStringsSep "\n" (app: ''
          ${ts} serve --service=svc:${app.name} --https=443 http://127.0.0.1:${toString app.port}
          ${ts} serve --service=svc:${app.name} --http=80 http://127.0.0.1:${toString app.redirectPort}
        '') apps}
        exec sleep infinity
      '';
    };
  };
}
