terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.100.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# SSH-nyckelpar för control → target
resource "tls_private_key" "ansible_control" {
  algorithm = "ED25519"
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

# Cloud-init snippet: lägg till control nodes pubkey på target
resource "proxmox_virtual_environment_file" "target_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = "pve"

  source_raw {
    file_name = "ansible-target-user-data.yaml"
    data      = <<-EOF
      #cloud-config
      ssh_authorized_keys:
        - ${tls_private_key.ansible_control.public_key_openssh}
    EOF
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
    user_data_file_id = proxmox_virtual_environment_file.target_user_data.id
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
  depends_on = [
    proxmox_virtual_environment_vm.ansible_control,
    proxmox_virtual_environment_vm.ansible_target,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      CONTROL_IP="${proxmox_virtual_environment_vm.ansible_control.ipv4_addresses[1][0]}"
      TARGET_IP="${proxmox_virtual_environment_vm.ansible_target.ipv4_addresses[1][0]}"

      echo "Väntar på SSH till ansible_control ($CONTROL_IP)..."
      until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
        ${var.vm_ssh_user}@$CONTROL_IP true 2>/dev/null; do sleep 5; done

      echo "Kopierar SSH-nyckel till control node..."
      echo '${tls_private_key.ansible_control.private_key_openssh}' | \
        ssh -o StrictHostKeyChecking=no ${var.vm_ssh_user}@$CONTROL_IP \
        'install -m 700 -d ~/.ssh && cat > ~/.ssh/ansible_ed25519 && chmod 600 ~/.ssh/ansible_ed25519'

      echo "Skriver inventory på control node..."
      ssh -o StrictHostKeyChecking=no ${var.vm_ssh_user}@$CONTROL_IP \
        "printf '[targets]\n$TARGET_IP ansible_user=${var.vm_ssh_user} ansible_ssh_private_key_file=~/.ssh/ansible_ed25519\n' > ~/inventory.ini"

      echo "Installerar Ansible på control node..."
      ssh -o StrictHostKeyChecking=no -o BatchMode=yes ${var.vm_ssh_user}@$CONTROL_IP \
        'until ! sudo fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock \
           /var/cache/apt/archives/lock >/dev/null 2>&1; do \
           echo "Väntar på apt-lås..."; sleep 3; done; \
         sudo apt-get update -qq && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible && \
         ansible --version'
    EOT
  }
}
