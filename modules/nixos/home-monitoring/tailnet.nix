{ lib, pkgs, ... }:
let
  apps = [
    { name = "home-assistant"; port = 8123; redirectPort = 8124; }
    { name = "grafana"; port = 3002; redirectPort = 3003; }
  ];
  servicesFor = app: {
    "${app.name}-tailnet" = {
      description = "Dedicated ${app.name} Tailscale identity";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "notify";
        ExecStart = "${pkgs.tailscale}/bin/tailscaled --tun=userspace-networking --statedir=/var/lib/home-monitoring/tailnet/${app.name} --state=/var/lib/home-monitoring/tailnet/${app.name}/tailscaled.state --socket=/run/${app.name}-tailnet/tailscaled.sock --port=0";
        StateDirectory = "home-monitoring/tailnet/${app.name}";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "${app.name}-tailnet";
        RuntimeDirectoryMode = "0700";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
    "${app.name}-tailnet-serve" = {
      description = "Publish ${app.name} at its private service address";
      wantedBy = [ "multi-user.target" ];
      requires = [ "${app.name}-tailnet.service" ];
      wants = [ "home-monitoring.service" "nginx.service" ];
      after = [ "${app.name}-tailnet.service" "home-monitoring.service" "nginx.service" ];
      partOf = [ "${app.name}-tailnet.service" ];
      path = [ pkgs.tailscale pkgs.coreutils ];
      serviceConfig = { Type = "simple"; Restart = "on-failure"; RestartSec = "15s"; };
      script = ''
        tailscale --socket=/run/${app.name}-tailnet/tailscaled.sock up \
          --hostname=${app.name} --accept-dns=false --accept-routes=false
        tailscale --socket=/run/${app.name}-tailnet/tailscaled.sock serve \
          --bg --https=443 http://127.0.0.1:${toString app.port}
        tailscale --socket=/run/${app.name}-tailnet/tailscaled.sock serve \
          --bg --http=80 http://127.0.0.1:${toString app.redirectPort}
        exec sleep infinity
      '';
    };
  };
in {
  systemd.services = lib.mkMerge (map servicesFor apps);
  services.nginx.enable = true;
  services.nginx.virtualHosts = builtins.listToAttrs (map (app: {
    name = "${app.name}-shortcut";
    value = {
      listen = [ { addr = "127.0.0.1"; port = app.redirectPort; } ];
      locations."/".return = "308 https://${app.name}.tailf3d82.ts.net$request_uri";
    };
  }) apps);
}
