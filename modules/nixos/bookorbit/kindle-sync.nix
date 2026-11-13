{ config, lib, pkgs, ... }:
let
  runtime = import ./kindle-runtime.nix { inherit pkgs; };
  cli = pkgs.writeShellApplication {
    name = "bookorbit-kindle-cli";
    runtimeInputs = [ runtime.python pkgs.util-linux ];
    text = ''
      umask 077
      export KINDL_PROFILE=android
      export KINDL_CONFIG=/var/lib/bookorbit-kindle/config.json
      unset KINDL_DEVICE_TYPE KINDL_SW KINDL_APP_NAME KINDL_APP_VERSION KINDL_OEM_PLATFORM
      unset KINDL_DEVICE_MODEL KINDL_OS_VERSION KINDL_REG KINDL_VOUCHER_VERSIONS KINDL_NO_VV
      exec 9>/run/lock/bookorbit-media.lock
      flock -n 9 || { echo "Another media operation is active; retry after it finishes." >&2; exit 75; }
      exec ${runtime.python}/bin/python3 -m kindl "$@"
    '';
  };
  runner = pkgs.writeShellApplication {
    name = "bookorbit-kindle-sync";
    runtimeInputs = [ runtime.python runtime.calibre runtime.initializeConfig pkgs.util-linux pkgs.coreutils pkgs.qpdf ];
    text = ''
      umask 077
      export KINDL_PROFILE=android
      export KINDLE_IMPORTER=${./kindle-import.py}
      unset KINDL_DEVICE_TYPE KINDL_SW KINDL_APP_NAME KINDL_APP_VERSION KINDL_OEM_PLATFORM
      unset KINDL_DEVICE_MODEL KINDL_OS_VERSION KINDL_REG KINDL_VOUCHER_VERSIONS KINDL_NO_VV
      exec 9>/run/lock/bookorbit-media.lock
      if ! flock -n 9; then
        echo "Another media operation is active; the next Kindle download run will retry."
        exit 0
      fi
      exec ${runtime.python}/bin/python3 ${./kindle-sync.py} "$@"
    '';
  };
in {
  config = lib.mkIf (config.personal.bookorbit.enable && config.personal.bookorbit.kindle.enable) {
    systemd.tmpfiles.rules = [ "d /var/lib/bookorbit-kindle 0700 root root -" ];
    environment.systemPackages = [ runner cli ];
    systemd.services.bookorbit-kindle-sync = {
      description = "Download and import all available Kindle library items";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "podman-bookorbit.service" ];
      unitConfig = {
        ConditionPathExists = "/var/lib/bookorbit-kindle/config.json";
        OnFailure = [ "bookorbit-alert-check.service" ];
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe runner;
        UMask = "0077";
        TimeoutStartSec = "6h";
        TimeoutStopSec = "30s";
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/bookorbit-kindle" "/srv/books" "/run/lock" ];
      };
    };
    systemd.timers.bookorbit-kindle-sync = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = "hourly"; RandomizedDelaySec = "10m"; Persistent = true; };
    };
  };
}
