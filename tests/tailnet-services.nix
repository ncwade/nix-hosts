# nix eval --impure --json --expr 'let f = builtins.getFlake ("path:" + toString ./.); in import ./tests/tailnet-services.nix { host = f.nixosConfigurations.tycho; }'
{ host }:
let
  lib = host.pkgs.lib;
  atPhase = phase: (host.extendModules {
    modules = [ { personal.tailnetServices.phase = lib.mkForce phase; } ];
  }).config;
  legacy = atPhase "legacy";
  prepare = atPhase "prepare";
  services = atPhase "services";
  oldUnits = [ "bookorbit-tailnet" "bookorbit-tailnet-serve"
    "home-assistant-tailnet" "home-assistant-tailnet-serve"
    "grafana-tailnet" "grafana-tailnet-serve" ];
  # These unit texts include rendered ExecStart paths. Equal values demonstrate
  # that switching publication does not restart apps, machine access, or SSO.
  unaffected = [ "tailscaled" "rex-login-server" "rex-tailscale-serve" "tsidp"
    "home-monitoring" "podman-bookorbit" "podman-bookorbit-db" "nginx" "llama-cpp"
    "bookorbit-serve" "bookorbit-kindle" "bookorbit-kindle-sync" "bookorbit-audible"
    "bookorbit-alert-check" ];
  unitText = c: name: c.systemd.units."${name}.service".text;
in
assert builtins.all (name: builtins.hasAttr name legacy.systemd.services
  && builtins.hasAttr name prepare.systemd.services
  && !(builtins.hasAttr name services.systemd.services)) oldUnits;
assert !(legacy.systemd.services ? tailnet-services);
assert prepare.systemd.services ? tailnet-services;
assert prepare.systemd.services ? tailnet-services-prepare;
assert !(prepare.systemd.services ? tailnet-services-publish);
assert services.systemd.services ? tailnet-services-publish;
assert !(services.systemd.services ? tailnet-services-prepare);
assert builtins.all (name: unitText legacy name == unitText prepare name
  && unitText legacy name == unitText services name) unaffected;
assert services.personal.tailnetServices.services.bookorbit.port == 3000;
assert services.personal.tailnetServices.services.home-assistant.port == 8123;
assert services.personal.tailnetServices.services.grafana.port == 3002;
assert services.personal.tailnetServices.services.llm.port == 8080;
assert builtins.attrNames services.personal.tailnetServices.services == [ "bookorbit" "grafana" "home-assistant" "llm" ];
assert services.networking.firewall.allowedTCPPorts == legacy.networking.firewall.allowedTCPPorts;
assert services.networking.firewall.interfaces == legacy.networking.firewall.interfaces;
assert services.services.tsidp.settings == legacy.services.tsidp.settings;
assert services.virtualisation.oci-containers.containers.bookorbit.environment.APP_URL == "https://bookorbit.tailf3d82.ts.net";
assert services.services.nginx.virtualHosts.grafana-shortcut.locations."/".return == "308 https://grafana.tailf3d82.ts.net$request_uri";
assert services.services.nginx.virtualHosts.home-assistant-shortcut.locations."/".return == "308 https://home-assistant.tailf3d82.ts.net$request_uri";
assert services.services.nginx.virtualHosts.llm-shortcut.locations."/".return == "308 https://llm.tailf3d82.ts.net$request_uri";
{
  legacy = legacy.system.build.toplevel.drvPath;
  prepare = prepare.system.build.toplevel.drvPath;
  services = services.system.build.toplevel.drvPath;
}
