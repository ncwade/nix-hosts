{ config, lib, pkgs, ... }:
let
  repository = "/mnt/Data/documents/backups/tycho/bookorbit";
  lock = "/run/lock/nas1-documents-backup.lock";
  sftp = pkgs.writeShellScript "nas1-bookorbit-sftp" ''
    set -eu
    ${pkgs.util-linux}/bin/mountpoint -q /mnt/Data/documents
    test -d ${repository}
    # Every SFTP connection holds the same exclusive lock as offsite rsync.
    # restic uses one connection for the lifetime of each repository operation.
    exec ${pkgs.util-linux}/bin/flock --exclusive --timeout 21600 ${lock} \
      ${pkgs.openssh}/libexec/sftp-server -d ${repository}
  '';
in {
  config = lib.mkIf config.personal.nas1.documents.enable {
    # Same owner as the offsite job: it can read restic's private 0600 files.
    # This account's SSH key can only invoke the locked SFTP endpoint.
    users.users.nas-backup.shell = pkgs.bash;
    services.openssh.extraConfig = ''
      Match User nas-backup
        AuthorizedKeysFile /etc/ssh/tycho-bookorbit-backup.pub
        ForceCommand ${sftp}
        DisableForwarding yes
        PermitTTY no
        PasswordAuthentication no
        KbdInteractiveAuthentication no
      Match all
    '';
    systemd.tmpfiles.rules = [
      "f ${lock} 0600 nas-backup nas-backup -"
    ];
    systemd.services.nas1-bookorbit-backup-directory = {
      description = "Create the encrypted BookOrbit backup destination inside documents";
      wantedBy = [ "multi-user.target" ];
      requires = [ "nas1-documents.service" ];
      after = [ "nas1-documents.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      path = [ pkgs.coreutils pkgs.util-linux ];
      script = ''
        set -eu
        mountpoint -q /mnt/Data/documents
        for parent in /mnt/Data/documents/backups /mnt/Data/documents/backups/tycho; do
          test ! -L "$parent"
          if [ ! -d "$parent" ]; then
            install -d -m 0750 -o nas-backup -g docs "$parent"
          fi
        done
        test ! -L ${repository}
        install -d -m 0700 -o nas-backup -g nas-backup ${repository}
      '';
    };
  };
}
