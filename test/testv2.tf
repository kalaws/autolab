terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.100.0" # Using the required version
    }
  }
}
# Provider is configured using environment args

provider "proxmox" {}

# ============================================
# 1. Slå upp Packer-byggt template
# ============================================
data "proxmox_virtual_environment_vms" "test-vm-sr" {
  node_name = "pve"
  filter {
    name   = "name"
    values = ["ubuntu-2404-q35-template"]
  }
}

resource "proxmox_virtual_environment_vm" "test_vm" {
  name        = "terraform-test"
  node_name   = "pve"

  clone {
    vm_id = data.proxmox_virtual_environment_vms.test-vm-sr.vms[0].vm_id
  }

  cpu { 
    cores = 1
  }
  memory {
    dedicated = 1024
  }
  network_device {
    model  = "virtio"
    bridge = "vnet1"
  }
  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }
{  stop on destroy = true
}
}
