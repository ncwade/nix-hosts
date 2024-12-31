ARCH ?= x86_64
ANYWHERE_RUN=github:nix-community/nixos-anywhere -- --flake '.\#devvm-$(ARCH)' --target-host root@192.0.2.1


vm/pack:
	packer build --var "iso_path=result/iso/nixos-25.05.20241229.88195a9-x86_64-linux.iso" nixos.pkr.hcl
vm/create:
	vagrant up
vm/destroy:
	vagrant destroy
vm/init:
	vagrant ssh -c "wget -O - https://github.com/ncwade.keys >> /home/vagrant/.ssh/authorized_keys"
host/nix:
	curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --determinate
vm/infect:
	nix run $(ANYWHERE_RUN)
vm/repair:
	nix run $(ANYWHERE_RUN) --phases install,reboot
