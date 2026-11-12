{ ... }:

{
  # NAS1's existing authenticated documents share. Keep the password in a
  # root-only file on Tycho, never in a Nix expression or the Nix store.
  fileSystems."/mnt/nas1/docs" = {
    device = "//192.168.3.63/docs";
    fsType = "cifs";
    options = [
      "credentials=/var/lib/samba/credentials/nas1-docs"
      "vers=3.1.1"
      "uid=ncwade"
      "gid=users"
      "forceuid"
      "forcegid"
      "file_mode=0600"
      "dir_mode=0700"
      "nosuid"
      "nodev"
      "noexec"
      "_netdev"
      "nofail"
      "x-systemd.automount"
      "x-systemd.idle-timeout=5min"
      "x-systemd.mount-timeout=30s"
    ];
  };
}
