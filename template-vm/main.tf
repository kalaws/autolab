terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.99.0" # Using the required version
    }
  }
}
# Provider is configured using environment args
provider "proxmox" {}




# ============================================
# 1. Ladda ner Ubuntu Jammy cloud image
# ============================================
#resource "proxmox_virtual_environment_download_file" "ubuntu_jammy_packer" {
#  content_type = "import"
#  datastore_id = "local"
#  node_name    = "pve"
#  url          = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
#  file_name    = "jammy-server-cloudimg-amd64.qcow2"
#}

# ============================================
# 2. Skapa template från cloud image
# ============================================
resource "proxmox_virtual_environment_vm" "ubuntu_jammy_packer_template" {
  name      = "ubuntu-jammy-packer"
  node_name = "pve"
  template  = true
  started   = false

  cpu {
    cores = 1
  }

  memory {
    dedicated = 1024
  }

  disk {
    datastore_id = "local-lvm"
    import_from  = "local:import/jammy-server-cloudimg-amd64.qcow2"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 10
  }

  network_device {
    bridge = var.bridge_autolab_wan
  }

  # Cloud-init: krävs för att kunna logga in
  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  # Krävs för att QEMU guest agent ska fungera
  agent {
    enabled = true
  }

  serial_device {}
}
