{ config, lib, pkgs, ... }:

let
  enabled = config.personal.nas1.documents.enable;
  documents = "/mnt/Data/documents";
  poolGuid = "3134546306779774706";
in
{
  options.personal.nas1.documents.enable = lib.mkEnableOption "the verified nas1 documents share and backup";

  config = lib.mkIf enabled {
    # Import only the existing pool and mount only documents. No pool creation,
    # property upgrades, recursive permissions changes, or other dataset mounts.
    systemd.services.nas1-documents = {
      description = "Import the existing NAS pool and mount documents";
      wantedBy = [ "multi-user.target" ];
      after = [ "zfs.target" ];
      before = [ "samba-smbd.service" "nas1-documents-backup.service" ];
      path = [ config.boot.zfs.package pkgs.util-linux pkgs.coreutils ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        set -euo pipefail
        if ! zpool list -H -o guid Data >/dev/null 2>&1; then
          zpool import -N -o cachefile=none -R /mnt -d /dev/disk/by-id ${poolGuid}
        fi
        test "$(zpool get -H -o value guid Data)" = ${poolGuid}
        test "$(zpool get -H -o value readonly Data)" = off
        test "$(zpool get -H -o value altroot Data)" = /mnt
        if ! mountpoint -q ${documents}; then
          zfs mount Data/documents
        fi
        test "$(findmnt -rn -M ${documents} -o SOURCE)" = Data/documents
      '';
      preStop = ''
        zfs unmount Data/documents
        zpool export Data
      '';
    };

    services.samba = {
      enable = true;
      nmbd.enable = false;
      winbindd.enable = false;
      openFirewall = false;
      settings = {
        global = {
          "server role" = "standalone server";
          "server min protocol" = "SMB2";
          "map to guest" = "Never";
          "load printers" = "no";
          "disable spoolss" = "yes";
        };
        docs = {
          path = documents;
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "docs";
          "force group" = "docs";
          "create mask" = "0660";
          "directory mask" = "0770";
          "vfs objects" = "fruit streams_xattr";
          "fruit:metadata" = "stream";
          "fruit:resource" = "stream";
          "ea support" = "yes";
        };
      };
    };
    networking.firewall.allowedTCPPorts = [ 445 ];
    systemd.services.samba-smbd = {
      requires = [ "nas1-documents.service" ];
      after = [ "nas1-documents.service" ];
      unitConfig.RequiresMountsFor = [ documents ];
      serviceConfig.ExecStartPre = [ "${pkgs.util-linux}/bin/mountpoint -q ${documents}" ];
    };

    users.groups.nas-backup.gid = 1002;
    users.users.nas-backup = {
      isSystemUser = true;
      uid = 1002;
      group = "nas-backup";
      extraGroups = [ "docs" ];
    };
    systemd.services.nas1-documents-backup = {
      description = "Back up documents to the existing rsync.net destination";
      requires = [ "nas1-documents.service" ];
      wants = [ "network-online.target" ];
      after = [ "nas1-documents.service" "network-online.target" ];
      unitConfig.RequiresMountsFor = [ documents ];
      serviceConfig = {
        Type = "oneshot";
        User = "nas-backup";
        Group = "nas-backup";
        SupplementaryGroups = [ "docs" ];
        LoadCredential = [
          "ssh-key:/var/lib/nas1-backup/id_rsa"
          "known-hosts:/var/lib/nas1-backup/known_hosts"
        ];
        ExecStartPre = "${pkgs.util-linux}/bin/mountpoint -q ${documents}";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        TimeoutStartSec = "6h";
      };
      # Preserve the existing rsync task's scope, destination, and deletion policy.
      script = ''
        exec ${pkgs.rsync}/bin/rsync -rt -zz --delay-updates --delete-delay --stats \
          -e "${pkgs.openssh}/bin/ssh -i $CREDENTIALS_DIRECTORY/ssh-key -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$CREDENTIALS_DIRECTORY/known-hosts" \
          ${documents} 3451@usw-s003.rsync.net:truenas/
      '';
    };
    systemd.timers.nas1-documents-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = "*-*-* 00:00:00"; Persistent = true; };
    };
  };
}
