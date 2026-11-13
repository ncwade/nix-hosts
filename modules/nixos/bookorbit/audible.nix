{ config, lib, pkgs, ... }:
let
  cfg = config.personal.bookorbit.audible;
  image = "docker.io/rmcrackan/libation:14.2.5@sha256:7bb47a417311d154c6691747320d0b62ce15527280ad99f0e2a85ac9a6b07e40";
  settings = pkgs.writeText "libation-settings.json" (builtins.toJSON {
    Books = "/books/audiobooks";
    InProgress = "/books/.libation-in-progress";
    FirstLaunch = false;
    FileDownloadQuality = "High";
    DecryptToLossy = false;
    UseWidevine = false;
    Request_xHE_AAC = false;
    SplitFilesByChapter = false;
    MoveMoovToBeginning = true;
    DownloadCoverArt = true;
    OverwriteExisting = false;
    ImportPlusTitles = false;
    ImportEpisodes = false;
    DownloadEpisodes = false;
    TokenStorageMethod = "Encrypted";
    FolderTemplate = "<title short> [<id>]";
    FileTemplate = "<title> [<id>]";
    MaxConcurrentDownloads = 1;
    DailyDownloadLimit = "NoLimit";
  });
  cli = pkgs.writeShellApplication {
    name = "bookorbit-audible-cli";
    runtimeInputs = [ pkgs.podman ];
    text = ''
      exec podman run --rm --name bookorbit-audible-cli \
        --user 2000:2000 --network=host --read-only \
        --cap-drop=ALL --security-opt=no-new-privileges \
        --tmpfs=/tmp:rw,nosuid,nodev --workdir=/config \
        --env HOME=/tmp --env TZ=America/Chicago \
        --env LIBATION_MASTER_KEY_FILE=/config/libation-master.key \
        --volume /var/lib/libation:/config \
        --volume /srv/books:/books \
        --entrypoint /libation/LibationCli \
        ${lib.escapeShellArg image} "$@" --libationFiles /config
    '';
  };
in {
  options.personal.bookorbit.audible.enable = lib.mkEnableOption "hourly Audible imports on the BookOrbit server";
  config = lib.mkIf (config.personal.bookorbit.enable && cfg.enable) {
    systemd.tmpfiles.rules = [
      "d /var/lib/libation 0700 bookorbit bookorbit -"
      "d /srv/books/.libation-in-progress 0700 bookorbit bookorbit -"
    ];
    environment.systemPackages = [ cli ];
    environment.etc."bookorbit/libation-settings.json".source = settings;
    environment.etc."bookorbit/libation-image".text = image + "\n";
    systemd.services.bookorbit-audible = {
      description = "Scan Audible and download missing purchases into BookOrbit";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "podman-bookorbit.service" ];
      unitConfig.ConditionPathExists = [
        "/var/lib/libation/AccountsSettings.json"
        "/var/lib/libation/libation-master.key"
      ];
      path = [ pkgs.coreutils pkgs.util-linux cli pkgs.python3 ];
      environment.AUDIBLE_HEALTH_CHECK = toString ./audible-health.py;
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
        TimeoutStartSec = "6h";
        TimeoutStopSec = "90s";
        ExecStopPost = "-${pkgs.podman}/bin/podman stop -t 60 bookorbit-audible-cli";
      };
      script = builtins.readFile ./audible.sh;
    };
    systemd.timers.bookorbit-audible = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "5m";
        Persistent = true;
      };
    };
  };
}
