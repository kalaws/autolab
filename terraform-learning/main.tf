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
    name = "terraform-learning-vm"
    node_name = "pve"
    vm_id = 300

    clone {
        vm_id = 116
    }

    cpu {
        cores = 1
    }

    memory {
        dedicated = 512
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