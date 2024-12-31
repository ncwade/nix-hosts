packer {
  required_version = ">= 1.1.0"
  required_plugins {
    vmware = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/vmware"
    }
  }
}

variable "iso_path" {
  type = string
}

source "vmware-iso" "devvm" {
  boot_command = [
    "<enter>"
  ]
  iso_checksum       = "none"
  iso_url            = var.iso_path
  vm_name            = "devvm"
  guest_os_type      = "other6xlinux-64"
  cpus               = 9
  cores              = 18
  memory             = 32000
  network            = "nat"
  firmware           = "efi"
  disk_size          = 80000
  disk_adapter_type  = "scsi"
  cdrom_adapter_type = "sata"
  vmx_data = {
    "mks.enable3d" : "TRUE",
    "svga.graphicsMemoryKB" : "8388608"
  }
  skip_export     = false
  keep_registered = true
  skip_compaction = true
  ssh_username    = "root"
  ssh_password    = ""
}

build {
  sources = ["source.vmware-iso.devvm"]
  provisioner "shell" {
    inline = [
      "git clone https://github.com/ncwade/nix-config.git",
      "cd nix-config",
      "nix --experimental-features "nix-command flakes" run github:nix-community/disko -- --mode disko ./hosts/devvm-disko.nix",
      "cp -r . /mnt/etc/nixos",
      "nixos-install --root /mnt --flake '/mnt/etc/nixos#devvm'"
    ]
  }
}
