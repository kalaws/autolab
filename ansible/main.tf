terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.100.0"
    }
  }
}

provider "proxmox" {}

# ============================================
# 1. Slå upp Packer-byggt template
# ============================================
data "proxmox_virtual_environment_vms" "packer_template" {
  node_name = "pve"
  filter {
    name   = "name"
    values = ["ubuntu-2404-q35-template"]
  }
}

# ============================================
# 2. VM:ar
# ============================================

# Ansible control node
resource "proxmox_virtual_environment_vm" "ansible_control" {
  name      = "LAB-ANSIBLE-control"
  node_name = "pve"

  clone {
    vm_id = data.proxmox_virtual_environment_vms.packer_template.vms[0].vm_id
  }

  memory {
    dedicated = 2048
  }

  network_device {
    bridge = var.bridge_wan
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  stop_on_destroy = true

  agent {
    enabled = true
  }
}

# Target node
resource "proxmox_virtual_environment_vm" "ansible_target" {
  name      = "LAB-ANSIBLE-target"
  node_name = "pve"

  clone {
    vm_id = data.proxmox_virtual_environment_vms.packer_template.vms[0].vm_id
  }

  memory {
    dedicated = 1024
  }

  network_device {
    bridge = var.bridge_wan
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  stop_on_destroy = true

  agent {
    enabled = true
  }
}

# ============================================
# 3. Installera Ansible på control node
# ============================================
resource "terraform_data" "install_ansible" {
  depends_on = [proxmox_virtual_environment_vm.ansible_control]

  provisioner "local-exec" {
    command = <<-EOT
      CONTROL_IP="${proxmox_virtual_environment_vm.ansible_control.ipv4_addresses[1][0]}"
      echo "Väntar på SSH till ansible_control ($CONTROL_IP)..."
      until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
        ${var.vm_ssh_user}@$CONTROL_IP true 2>/dev/null; do sleep 5; done

      echo "Installerar Ansible på control node..."
      ssh -o StrictHostKeyChecking=no -o BatchMode=yes ${var.vm_ssh_user}@$CONTROL_IP \
        'sudo apt-get update -qq && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible && \
         ansible --version'
    EOT
  }
}
