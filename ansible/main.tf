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
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
}

# Deploy key för git clone på control node
resource "tls_private_key" "deploy_key" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "deploy_private_key" {
  content         = tls_private_key.deploy_key.private_key_openssh
  filename        = "${path.module}/.deploy_ed25519"
  file_permission = "0600"
}

resource "github_repository_deploy_key" "autolab" {
  title      = "LAB-ANSIBLE-control"
  repository = "autolab"
  key        = tls_private_key.deploy_key.public_key_openssh
  read_only  = true
}

provider "proxmox" {}
provider "github" {
  owner = var.github_owner
}

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

# Enumerate ansible target IPs
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
    github_repository_deploy_key.autolab,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      CONTROL_IP="${proxmox_virtual_environment_vm.ansible_control.ipv4_addresses[1][0]}"
      SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes"

      echo "Väntar på SSH till ansible_control ($CONTROL_IP)..."
      until ssh $SSH_OPTS ${var.vm_ssh_user}@$CONTROL_IP true 2>/dev/null; do sleep 5; done

      echo "Genererar SSH-nyckelpar på ansible control..."
      ssh $SSH_OPTS ${var.vm_ssh_user}@$CONTROL_IP \
        "ssh-keygen -t ed25519 -f ~/.ssh/ansible_ed25519 -N '' -C 'ansible-control'"

      echo "Hämtar pubkey från ansible control..."
      ANSIBLE_PUBKEY=$(ssh $SSH_OPTS ${var.vm_ssh_user}@$CONTROL_IP "cat ~/.ssh/ansible_ed25519.pub")

      # Vänta på alla targets och lägg till pubkey
      for TARGET_IP in ${join(" ", values(local.target_ips))}; do
        echo "Väntar på SSH till $TARGET_IP..."
        until ssh $SSH_OPTS ${var.vm_ssh_user}@$TARGET_IP true 2>/dev/null; do sleep 5; done

        echo "Lägger till control nodes pubkey på $TARGET_IP..."
        ssh $SSH_OPTS ${var.vm_ssh_user}@$TARGET_IP \
          "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$ANSIBLE_PUBKEY' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
      done

      echo "Kopierar deploy key till ansible control..."
      scp $SSH_OPTS ${local_sensitive_file.deploy_private_key.filename} ${var.vm_ssh_user}@$CONTROL_IP:.ssh/deploy_ed25519

      echo "Skriver SSH-config på ansible control node..."
      ssh $SSH_OPTS ${var.vm_ssh_user}@$CONTROL_IP \
        "printf 'Host 10.*\n  User ${var.vm_ssh_user}\n  IdentityFile ~/.ssh/ansible_ed25519\n  StrictHostKeyChecking no\n\nHost github.com\n  IdentityFile ~/.ssh/deploy_ed25519\n  StrictHostKeyChecking no\n' > ~/.ssh/config && chmod 600 ~/.ssh/config"

      echo "Skriver inventory på ansible control node..."
      ssh $SSH_OPTS ${var.vm_ssh_user}@$CONTROL_IP \
        "printf '[targets]\n${join("\\n", [for ip in values(local.target_ips) : "${ip} ansible_user=${var.vm_ssh_user} ansible_ssh_private_key_file=~/.ssh/ansible_ed25519"])}\n' > ~/inventory.ini"

      echo "Installerar Ansible på ansible control node..."
      ssh $SSH_OPTS ${var.vm_ssh_user}@$CONTROL_IP \
        'sudo cloud-init status --wait && \
         sudo apt-get -o DPkg::Lock::Timeout=300 update -qq && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 upgrade -y && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y ansible git && \
         ansible --version'

      echo "Klonar repot på ansible control node..."
      ssh $SSH_OPTS ${var.vm_ssh_user}@$CONTROL_IP \
        "git clone -b ${var.github_branch} git@github.com:${var.github_owner}/autolab.git ~/autolab"
    EOT
  }
}
