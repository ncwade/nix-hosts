{
  config,
  lib,
  pkgs,
  ...
}:

let
  source = config.personal.books.nfsSource;
  enabled = source != null;
  libraryPath = "/srv/books";
in
{
  options.personal.books.nfsSource = lib.mkOption {
    type = lib.types.nullOr lib.types.nonEmptyStr;
    default = null;
    example = "192.168.1.10:/mnt/tank/books";
    description = "TrueNAS NFSv4 export. Null disables the mount and Audiobookshelf until storage is ready.";
  };

  config = lib.mkMerge [
    {
      warnings = lib.optional (
        !enabled
      ) "Tycho: TrueNAS is not configured; set personal.books.nfsSource to enable the book library.";

      # Reserve ownership even while the library is disabled.
      users.users.audiobookshelf = {
        isSystemUser = true;
        group = "audiobookshelf";
        home = "/var/lib/audiobookshelf";
      };
      users.groups.audiobookshelf = { };
    }
    (lib.mkIf enabled {
      fileSystems.${libraryPath} = {
        device = source;
        fsType = "nfs";
        options = [
          "nfsvers=4.2"
          "hard"
          "_netdev"
          "nofail"
          "noauto"
          "nosuid"
          "nodev"
          "noexec"
          "x-systemd.mount-timeout=30s"
        ];
      };

      services.audiobookshelf = {
        enable = true;
        host = "127.0.0.1";
        port = 8000;
        openFirewall = false;
        # SQLite, covers, and progress stay on the local SSD.
        dataDir = "audiobookshelf";
      };

      systemd.services.audiobookshelf = {
        # Pull in the real mount (even with noauto); never scan a bare local
        # directory. A failed NAS mount fails this service, not the OS boot.
        unitConfig.RequiresMountsFor = [ libraryPath ];
        bindsTo = [ "srv-books.mount" ];
        after = [ "srv-books.mount" ];
        serviceConfig.ExecStartPre = "${pkgs.util-linux}/bin/mountpoint --quiet ${libraryPath}";
      };
    })
  ];
}
