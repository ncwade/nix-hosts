{ lib, pkgs, ... }:
let
  # Only runtime assets determine the Compose configuration path. Unrelated
  # repository edits must not recreate containers or interrupt collection.
  source = builtins.path {
    path = ./.;
    name = "home-monitoring";
    filter = path: _: builtins.baseNameOf path != "__pycache__" && !(lib.hasSuffix ".nix" path);
  };
  compose = "${pkgs.docker}/bin/docker compose -f ${source}/compose.yaml";
  oidc = pkgs.fetchurl {
    url = "https://github.com/christiaangoossens/hass-oidc-auth/releases/download/v1.2.1/hass-oidc-auth.zip";
    sha256 = "e5badaaacaa63cfd6fe733924a05e76d75058836190398598fb24de57cd47ccd";
  };
in {
  imports = [ ./tailnet.nix ];
  virtualisation.docker.enable = true;
  environment.systemPackages = [ pkgs.docker-compose pkgs.python3 ];
  systemd.tmpfiles.rules = [ "d /var/lib/home-monitoring 0711 root root -" ];
  systemd.services.home-monitoring = {
    description = "Home Assistant, InfluxDB, and Grafana monitoring";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    requires = [ "docker.service" ];
    after = [ "docker.service" "network-online.target" ];
    path = [ pkgs.docker pkgs.docker-compose pkgs.coreutils pkgs.python3 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = 900;
      UMask = "0077";
      ExecStop = "${compose} stop";
    };
    script = ''
      install -d -m 0700 /var/lib/home-monitoring/secrets /var/lib/home-monitoring/home-assistant/packages
      touch /var/lib/home-monitoring/secrets/grafana.env
      ${compose} stop home-assistant
      ${compose} up -d influxdb
      python3 ${source}/bootstrap.py
      python3 ${source}/configure_http.py
      python3 ${source}/configure_homeassistant.py ${source}/home-assistant/configuration.yaml
      python3 ${source}/configure_sso.py ${oidc}
      python3 ${source}/configure_alerting.py
      install -m 0600 ${source}/home-assistant/tcc.yaml /var/lib/home-monitoring/home-assistant/packages/tcc.yaml
      ${compose} up -d --remove-orphans
    '';
  };
  systemd.services.home-monitoring-backup = {
    description = "Encrypted thermostat monitoring backup to NAS1";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [ pkgs.coreutils pkgs.rsync pkgs.util-linux pkgs.systemd pkgs.docker ];
    serviceConfig = { Type = "oneshot"; UMask = "0077"; TimeoutStartSec = "2h"; };
    script = builtins.readFile ../../../scripts/backup-home-monitoring.sh;
  };
  systemd.timers.home-monitoring-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*-*-* 02:30:00 America/Chicago"; Persistent = true; };
  };
}
