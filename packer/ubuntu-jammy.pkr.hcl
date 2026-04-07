packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = "~> 1"
    }
  }
}

source "proxmox-iso" "ubuntu_jammy" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = true
  node                     = "pve"

  vm_name              = "ubuntu-jammy-packer"
  template_description = "Ubuntu Jammy med qemu-guest-agent – byggd av Packer"

  boot_iso {
    iso_file         = var.iso_file
    iso_storage_pool = "local"
    unmount          = true
  }

  # Cloud-init seed ISO (NoCloud datasource)
  additional_iso_files {
    cd_label = "cidata"
    cd_files = [
      "${path.root}/cloud-init/user-data",
      "${path.root}/cloud-init/meta-data",
    ]
    iso_storage_pool = "local"
    unmount          = true
  }

  cpu_type = "host"
  cores    = 1
  memory   = 1024

  disks {
    disk_size    = "10G"
    storage_pool = "local-lvm"
    type         = "virtio"
  }

  network_adapters {
    bridge = var.bridge_wan
    model  = "virtio"
  }

  qemu_agent = true

  # Boota från Ubuntu ISO (ide2), sedan disk
  boot = "order=ide2;virtio0"

  # Autoinstall triggas via kernel-param
  boot_wait = "5s"
  boot_command = [
    "<wait>e<wait>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud",
    "<f10>"
  ]

  # Inget SSH – allt sköts av autoinstall + Proxmox API
  communicator = "none"

}

build {
  sources = ["source.proxmox-iso.ubuntu_jammy"]
}
