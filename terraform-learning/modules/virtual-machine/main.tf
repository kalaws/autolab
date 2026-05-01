terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.100.0"
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
    name = var.vm_name
    node_name = var.node_name
    vm_id = var.vm_id

    clone {
        vm_id = var.clone_id
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