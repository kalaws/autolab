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
    cd_content = {
      "user-data" = templatefile("${path.root}/cloud-init/user-data.tpl", {
        ssh_public_key = trimspace(file(var.ssh_public_key_file))
      })
      "meta-data" = ""
    }
    iso_storage_pool = "local"
    unmount          = true
  }

  machine  = "q35"
  bios     = "ovmf"
  cpu_type = "host"
  cores    = 1
  memory   = 1024

  efi_config {
    efi_storage_pool  = "local-lvm"
    pre_enrolled_keys = false
    efi_type          = "4m"
  }

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

  # Boota från Ubuntu ISO, sedan disk
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
