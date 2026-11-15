{ config, lib, pkgs, ... }:
let
  cfg = config.personal.bookorbit;
  monitor = pkgs.writeShellApplication {
    name = "bookorbit-alert-check";
    runtimeInputs = [ pkgs.python3 pkgs.systemd ];
    text = ''exec python3 ${./alerts.py} "$@"'';
  };
in {
  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.systemd.services ? home-monitoring;
      message = "BookOrbit alerts require the home-monitoring Grafana/InfluxDB stack.";
    }];
    systemd.tmpfiles.rules = [
      "d /var/lib/bookorbit-alerts 0700 root root -"
      "d /var/lib/bookorbit-connector-health 0700 root root -"
    ];
    environment.systemPackages = [ monitor ];
    systemd.services.bookorbit-alert-check = {
      description = "Export connector incident health for Grafana alerts";
      wants = [ "home-monitoring.service" ];
      after = [ "home-monitoring.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe monitor;
        Environment = "BOOKORBIT_INFLUX_TOKEN_FILE=/var/lib/home-monitoring/secrets/bookorbit-write-token";
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
