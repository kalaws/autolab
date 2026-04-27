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
    name = var.vm_name
    node_name = "pve"
    vm_id = var.vm_id

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