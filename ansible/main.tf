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

# SSH-nyckelpar för control → targets
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

# Target nodes
resource "proxmox_virtual_environment_vm" "ansible_target" {
  for_each  = toset(var.targets)
  name      = "LAB-ANSIBLE-${each.key}"
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
# 3. Installera Ansible + konfigurera targets
# ============================================
locals {
  target_ips = {
    for name, vm in proxmox_virtual_environment_vm.ansible_target :
    name => vm.ipv4_addresses[1][0]
  }
}

resource "terraform_data" "install_ansible" {
  depends_on = [
    proxmox_virtual_environment_vm.ansible_control,
    proxmox_virtual_environment_vm.ansible_target,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      CONTROL_IP="${proxmox_virtual_environment_vm.ansible_control.ipv4_addresses[1][0]}"
      SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes"

      echo "Väntar på SSH till ansible_control ($CONTROL_IP)..."
      until ssh $SSH_OPTS ${var.vm_ssh_user}@$CONTROL_IP true 2>/dev/null; do sleep 5; done

      # Vänta på alla targets och lägg till pubkey
      for TARGET_IP in ${join(" ", values(local.target_ips))}; do
        echo "Väntar på SSH till $TARGET_IP..."
        until ssh $SSH_OPTS ${var.vm_ssh_user}@$TARGET_IP true 2>/dev/null; do sleep 5; done

        echo "Lägger till control nodes pubkey på $TARGET_IP..."
        ssh $SSH_OPTS ${var.vm_ssh_user}@$TARGET_IP \
          "mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
           echo '${tls_private_key.ansible_control.public_key_openssh}' >> ~/.ssh/authorized_keys && \
           chmod 600 ~/.ssh/authorized_keys"
      done

      echo "Kopierar SSH-nyckel till control node..."
      echo '${tls_private_key.ansible_control.private_key_openssh}' | \
        ssh $SSH_OPTS ${var.vm_ssh_user}@$CONTROL_IP \
        'install -m 700 -d ~/.ssh && cat > ~/.ssh/ansible_ed25519 && chmod 600 ~/.ssh/ansible_ed25519'

      echo "Skriver inventory på control node..."
      ssh $SSH_OPTS ${var.vm_ssh_user}@$CONTROL_IP \
        "printf '[targets]\n${join("\\n", [for ip in values(local.target_ips) : "${ip} ansible_user=${var.vm_ssh_user} ansible_ssh_private_key_file=~/.ssh/ansible_ed25519"])}\n' > ~/inventory.ini"

      echo "Installerar Ansible på control node..."
      ssh $SSH_OPTS ${var.vm_ssh_user}@$CONTROL_IP \
        'sudo apt-get -o DPkg::Lock::Timeout=300 update -qq && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 upgrade -y && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y ansible && \
         ansible --version'
    EOT
  }
}
