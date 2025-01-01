ARCH ?= intel

result/iso/nix-base.iso:
	nix build .#isoConfigs.base-iso-$(ARCH).config.system.build.isoImage

vm: result/iso/nix-base.iso
	packer build --var "iso_path=result/iso/nix-base.iso" --var "arch=$(ARCH)" nixos.pkr.hcl

host/nix:
	curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --determinate
