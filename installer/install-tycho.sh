#!/usr/bin/env bash
set -euo pipefail

: "${TYCHO_SYSTEM:?Run install-tycho from the Tycho installer ISO.}"
: "${TYCHO_CONFIG:?Run install-tycho from the Tycho installer ISO.}"

if [[ $EUID -ne 0 || ! -d /sys/firmware/efi || ! -t 0 ]]; then
  echo "Boot the Tycho USB in UEFI mode and run this installer through SSH with a terminal (ssh -t), or at its console."
  exit 1
fi

echo "Install Tycho — Framework Desktop, Ryzen AI Max+ 395 / 64 GB"
echo "This installs the prepared NixOS system. TrueNAS setup happens later."
echo "Available drives:"
lsblk -d -o PATH,SIZE,MODEL,SERIAL,TRAN
read -r -p "Enter the target NVMe disk (for example /dev/nvme0n1), or Ctrl-C to cancel: " disk

# Restrict installation to a whole NVMe device; never select a disk implicitly.
if [[ ! $disk =~ ^/dev/nvme[0-9]+n[0-9]+$ || ! -b $disk ]]; then
  echo "Choose a whole NVMe disk, not a partition or the USB installer."
  exit 1
fi
if [[ $(lsblk -dn -o TYPE "$disk") != disk || $(lsblk -dn -o RO "$disk") != 0 ]]; then
  echo "The selected device is not a writable disk."
  exit 1
fi
if lsblk -nr -o MOUNTPOINTS "$disk" | grep -q '[^[:space:]]'; then
  echo "The selected disk has mounted filesystems or active swap. Stop and inspect it first."
  exit 1
fi
if mountpoint -q /mnt; then
  echo "/mnt is already mounted. Stop and inspect the existing installation first."
  exit 1
fi

lsblk -d -o PATH,SIZE,MODEL,SERIAL "$disk"
echo "ALL DATA on $disk will be erased."
read -r -p "Type ERASE $disk to continue: " confirmation
if [[ $confirmation != "ERASE $disk" ]]; then
  echo "Cancelled. No disks changed."
  exit 1
fi

parted --script "$disk" -- mklabel gpt
parted --script "$disk" -- mkpart ESP fat32 1MiB 1025MiB
parted --script "$disk" -- set 1 esp on
parted --script "$disk" -- mkpart root ext4 1025MiB 100%
partprobe "$disk"
udevadm settle
mkfs.fat -F 32 -n TYCHO-BOOT "${disk}p1"
mkfs.ext4 -F -L tycho-root "${disk}p2"
udevadm settle
mkdir -p /mnt
# Avoid stale filesystem probes immediately after repartitioning/formatting.
mount -t ext4 "${disk}p2" /mnt
mkdir -p /mnt/boot
mount -t vfat -o fmask=0077,dmask=0077 "${disk}p1" /mnt/boot

# Keep a writable source snapshot for later rebuilds; never copy credentials.
mkdir -p /mnt/etc/nixos
cp -R "$TYCHO_CONFIG"/. /mnt/etc/nixos/
chmod -R u+w /mnt/etc/nixos
# Save actual hardware discovery for comparison with our planned disk layout.
nixos-generate-config --root /mnt --show-hardware-config > /mnt/etc/nixos/hardware-detected.nix
nixos-install --root /mnt --system "$TYCHO_SYSTEM" --no-channel-copy --no-root-passwd \
  --option substituters ""

echo "Set the ncwade password for console login and sudo."
nixos-enter --root /mnt -c 'passwd ncwade'
sync
umount -R /mnt
echo "Installation complete. Remove the USB after shutdown."
echo "After boot: connect from Luna with ssh ncwade@tycho.local."
echo "Then run sudo tailscale up --ssh to enroll in the personal tailnet."
echo "The setup guide is at /etc/nixos/docs/tycho.md."
read -r -p "Press Enter to shut down, or Ctrl-C to stay in the live environment: " _
poweroff
