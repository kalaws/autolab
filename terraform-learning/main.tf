terraform {
    required_providers {
      proxmox = {
        source = "bpg/proxmox"
        version = "~> 0.100.0"
      }
    }
}


provider "proxmox" {}

resource "proxmox_virtual_environment_vm" "learning_vm" {
    count = var.vm_count
    name = "terraform-learing-vm-${count.index + 1}"
    node_name = "pve"
    vm_id = 300 + count.index

    clone {
        vm_id = 116
    }

    cpu {
        cores = var.cpu_cores
    }

    memory {
        dedicated = var.memory
    }

    agent {
        enabled = false
    }

    network_device {
        bridge = "vmbr0"
        model = "virtio"
    }

    initialization {
        ip_config {
            ipv4 {
                address = "dhcp"
            }
        }
    }
}