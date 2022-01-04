# Connectivity info for Linux VM
NIXADDR ?= localhost
NIXPORT ?= 22
NIXADMIN ?= root
NIXUSER ?= ncwade

# Settings
NIXBLOCKDEVICE= sda

# Get the path to this Makefile and directory
MAKEFILE_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# The name of the nixosConfiguration in the flake
NIXNAME= vm-intel

# SSH options that are used. These aren't meant to be overridden but are
# reused a lot so we just store them up here.
SSH_OPTIONS=-o PubkeyAuthentication=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no

vm/install:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXADMIN)@$(NIXADDR) " \
		parted /dev/$(NIXBLOCKDEVICE) -- mklabel gpt; \
		parted /dev/$(NIXBLOCKDEVICE) -- mkpart primary 512MiB -8GiB; \
		parted /dev/$(NIXBLOCKDEVICE) -- mkpart primary linux-swap -8GiB 100\%; \
		parted /dev/$(NIXBLOCKDEVICE) -- mkpart ESP fat32 1MiB 512MiB; \
		parted /dev/$(NIXBLOCKDEVICE) -- set 3 esp on; \
		mkfs.ext4 -L nixos /dev/$(NIXBLOCKDEVICE)1; \
		mkswap -L swap /dev/$(NIXBLOCKDEVICE)2; \
		mkfs.fat -F 32 -n boot /dev/$(NIXBLOCKDEVICE)3; \
		mount /dev/disk/by-label/nixos /mnt; \
		mkdir -p /mnt/boot; \
		mount /dev/disk/by-label/boot /mnt/boot; \
		nixos-generate-config --root /mnt; \
	"
	scp $(SSH_OPTIONS) -p$(NIXPORT) -r $(MAKEFILE_DIR)/* $(NIXADMIN)@$(NIXADDR):/mnt/etc/nixos/
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXADMIN)@$(NIXADDR) " \
		sed -i 's/<replace me>/intel-vm/g' /mnt/etc/nixos/configuration.nix; \
		nixos-install --no-root-passwd; \
	"
vm/reboot:
	-ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXADMIN)@$(NIXADDR) " \
		reboot; \
	"
vm/switch:
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) "mkdir -p /tmp/nixos"
	scp $(SSH_OPTIONS) -p$(NIXPORT) -r $(MAKEFILE_DIR)/* $(NIXUSER)@$(NIXADDR):/tmp/nixos/
	ssh $(SSH_OPTIONS) -p$(NIXPORT) $(NIXUSER)@$(NIXADDR) " \
		sudo cp -r /tmp/nixos/* /etc/nixos/ && \
		sudo rm -rf /tmp/nixos/ && \
		sudo sed -i 's/<replace me>/intel-vm/g' /etc/nixos/configuration.nix && \
		sudo nixos-rebuild switch \
	"
