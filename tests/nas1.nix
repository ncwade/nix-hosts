{ host }:
let
  c = host.config;
  bootDevice = "/dev/disk/by-id/ata-16GB_SATA_Flash_Drive_E02214117000000042BA";
in
assert builtins.attrNames c.disko.devices.disk == [ "boot" ];
assert c.disko.devices.disk.boot.device == bootDevice;
assert c.disko.devices.zpool == { };
assert c.boot.zfs.extraPools == [ ];
assert !c.boot.zfs.forceImportAll;
assert builtins.all (fs: fs.fsType != "zfs") (builtins.attrValues c.fileSystems);
{
  inherit bootDevice;
  zfsVersion = c.boot.zfs.package.version;
  automaticDataImport = c.personal.nas1.documents.enable;
  filesystems = builtins.attrNames c.fileSystems;
}
