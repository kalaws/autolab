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

resource "proxmox_vm_qemu" "test_vm" {
  name        = "terraform-test"
  target_node = "proxmox"

  clone {
    vm_id = "ubuntu-2404-q35-template"
  }

  cpu { 
    cores = 1
  }
  memory {
    dedicated = 1024
  }
  network {
    model  = "virtio"
    bridge = "vmbr0"
  }
}
