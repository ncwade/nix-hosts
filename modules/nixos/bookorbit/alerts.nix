{ config, lib, pkgs, ... }:
let
  cfg = config.personal.bookorbit;
  python = pkgs.python3.withPackages (p: [ p.bcrypt ]);
  monitor = pkgs.writeShellApplication {
    name = "bookorbit-alert-check";
    runtimeInputs = [ pkgs.python3 pkgs.systemd ];
    text = ''exec python3 ${./alerts.py} "$@"'';
  };
in {
  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      environmentFile = "/var/lib/bookorbit-alerts/ntfy.env";
      settings = {
        base-url = "https://tycho.tailf3d82.ts.net:8443";
        listen-http = "127.0.0.1:2586";
        auth-default-access = "deny-all";
        auth-access = [ "bookorbit-publisher:bookorbit:write-only" "ncwade:bookorbit:read-only" ];
        enable-login = true;
        enable-signup = false;
        upstream-base-url = "https://ntfy.sh";
        cache-duration = "168h";
        attachment-cache-dir = lib.mkForce "";
      };
    };
    systemd.tmpfiles.rules = [
      "d /var/lib/bookorbit-alerts 0700 root root -"
      "d /var/lib/bookorbit-connector-health 0700 root root -"
    ];
    systemd.services.bookorbit-alert-secrets = {
      description = "Provision private ntfy connector credentials";
      before = [ "ntfy-sh.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; UMask = "0077"; };
      script = ''${python}/bin/python3 ${./alert-secrets.py}'';
    };
    systemd.services.ntfy-sh = {
      requires = [ "bookorbit-alert-secrets.service" ];
      after = [ "bookorbit-alert-secrets.service" ];
    };
    systemd.services.bookorbit-alert-serve = {
      description = "Publish private ntfy over Tycho's Tailscale HTTPS";
      wantedBy = [ "multi-user.target" ];
      requires = [ "tailscaled.service" ];
      wants = [ "ntfy-sh.service" ];
      after = [ "tailscaled.service" "ntfy-sh.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=8443 http://127.0.0.1:2586";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=8443 off";
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };
    environment.systemPackages = [ monitor ];
    systemd.services.bookorbit-alert-check = {
      description = "Send deduplicated connector failure and recovery alerts";
      wants = [ "ntfy-sh.service" ];
      after = [ "ntfy-sh.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe monitor;
        UMask = "0077";
        TimeoutStartSec = "50s";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/bookorbit-alerts" ];
      };
    };
    systemd.timers.bookorbit-alert-check = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnBootSec = "2min"; OnUnitActiveSec = "1min"; };
    };
    systemd.services.bookorbit-audible.unitConfig.OnFailure = [ "bookorbit-alert-check.service" ];
    systemd.services.bookorbit-kindle.unitConfig.OnFailure = [ "bookorbit-alert-check.service" ];
  };
}
