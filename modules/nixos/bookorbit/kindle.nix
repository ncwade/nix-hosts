{ config, lib, pkgs, ... }:
let
  cfg = config.personal.bookorbit.kindle;
  importer = pkgs.writeShellApplication {
    name = "bookorbit-kindle-import";
    runtimeInputs = [ pkgs.python3 pkgs.qpdf pkgs.util-linux pkgs.coreutils ];
    text = ''
      umask 077
      exec 9>/run/lock/bookorbit-media.lock
      if ! flock -n 9; then
        echo "Another media operation is active; the next Kindle timer will retry."
        exit 0
      fi
      python3 ${./kindle-import.py} \
        --inbox /srv/kindle-inbox --books /srv/books/ebooks \
        --state /srv/books/.kindle-import "$@"
      touch /var/lib/bookorbit-connector-health/kindle-success
    '';
  };
in {
  options.personal.bookorbit.kindle = {
    enable = lib.mkEnableOption "automatic import of exported Kindle EPUB/PDF files";
    uploader = lib.mkOption {
      type = lib.types.str;
      default = "ncwade";
      description = "Existing local account allowed to queue completed Kindle exports.";
    };
  };
  config = lib.mkIf (config.personal.bookorbit.enable && cfg.enable) {
    systemd.tmpfiles.rules = [
      "d /srv/kindle-inbox 0700 ${cfg.uploader} users -"
      "d /srv/books/.kindle-import 0700 root root -"
    ];
    environment.systemPackages = [ importer ];
    systemd.services.bookorbit-kindle = {
      description = "Import completed Kindle exports into BookOrbit";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe importer;
        UMask = "0077";
        TimeoutStartSec = "15min";
        PrivateNetwork = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadOnlyPaths = [ "/srv/kindle-inbox" ];
        ReadWritePaths = [ "/srv/books" "/run/lock" "/var/lib/bookorbit-connector-health" ];
        NoNewPrivileges = true;
      };
    };
    systemd.timers.bookorbit-kindle = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:0/5";
        Persistent = true;
      };
    };
  };
}
