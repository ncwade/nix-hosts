{
  # DESTRUCTIVE WHEN EXECUTED: only this observed 16 GB boot device is named.
  # Data's five disks and existing ZFS pool MUST NOT be added to disko.
  disko.devices.disk.boot = {
    type = "disk";
    device = "/dev/disk/by-id/ata-16GB_SATA_Flash_Drive_E02214117000000042BA";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "fmask=0077" "dmask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
