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

provider "proxmox" {}
provider "github" {
  owner = var.github_owner
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
  title      = "LAB-ANSIBLE-CT-control"
  repository = "autolab"
  key        = tls_private_key.deploy_key.public_key_openssh
  read_only  = true
}

# SSH-nyckel för Terraform → CT-åtkomst (injiceras via user_account.keys)
resource "tls_private_key" "terraform_ssh" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "terraform_ssh_private" {
  content         = tls_private_key.terraform_ssh.private_key_openssh
  filename        = "${path.module}/.terraform_ed25519"
  file_permission = "0600"
}

# SSH-nyckel för ansible control → targets (injiceras i targets via API, privnyckel kopieras till control)
resource "tls_private_key" "ansible_ssh" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "ansible_ssh_private" {
  content         = tls_private_key.ansible_ssh.private_key_openssh
  filename        = "${path.module}/.ansible_ed25519"
  file_permission = "0600"
}

# ============================================
# 1. Ansible control CT
# ============================================
resource "proxmox_virtual_environment_container" "ansible_control" {
  description = "Ansible control node (CT)"
  node_name   = "pve"
  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = "LAB-ANSIBLE-CT-control"

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [trimspace(tls_private_key.terraform_ssh.public_key_openssh), trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge_wan
  }

  operating_system {
    template_file_id = var.ct_template
    type             = "ubuntu"
  }

  memory {
    dedicated = 2048
    swap      = 512
  }

  cpu {
    architecture = "amd64"
    cores        = 1
  }

  disk {
    datastore_id = var.ct_disk_storage
    size         = 8
  }

  started = true
}

# ============================================
# 2. Target CT:ar
# ============================================
resource "proxmox_virtual_environment_container" "ansible_target" {
  for_each     = toset(var.targets)
  description  = "Ansible target CT ${each.key}"
  node_name    = "pve"
  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = "LAB-ANSIBLE-CT-${each.key}"

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [trimspace(tls_private_key.ansible_ssh.public_key_openssh), trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge_wan
  }

  operating_system {
    template_file_id = var.ct_template
    type             = "ubuntu"
  }

  memory {
    dedicated = 1024
    swap      = 512
  }

  cpu {
    architecture = "amd64"
    cores        = 1
  }

  disk {
    datastore_id = var.ct_disk_storage
    size         = 8
  }

  started = true
}

locals {
  control_ip = proxmox_virtual_environment_container.ansible_control.ipv4["eth0"]
  target_ips = {
    for name, ct in proxmox_virtual_environment_container.ansible_target :
    name => ct.ipv4["eth0"]
  }
}

# ============================================
# 3. Bootstrappa control node
# ============================================
resource "terraform_data" "bootstrap_control" {
  depends_on = [
    proxmox_virtual_environment_container.ansible_control,
    github_repository_deploy_key.autolab,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      CONTROL_IP="${local.control_ip}"
      SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.terraform_ssh_private.filename}"

      echo "Väntar på SSH till ansible_control ($CONTROL_IP)..."
      until ssh $SSH_OPTS ${var.ct_ssh_user}@$CONTROL_IP true 2>/dev/null; do sleep 5; done

      echo "Hämtar gateway från ansible control..."
      CONTROL_GW=$(ssh $SSH_OPTS ${var.ct_ssh_user}@$CONTROL_IP "ip route show default | awk '{print \$3; exit}'")
      echo "Gateway: $CONTROL_GW"

      echo "Konfigurerar DNS på ansible control ($CONTROL_GW)..."
      ssh $SSH_OPTS ${var.ct_ssh_user}@$CONTROL_IP \
        "{ echo 'nameserver $CONTROL_GW'; %{ for dns in var.dns_servers ~}echo 'nameserver ${dns}'; %{ endfor ~}} > /etc/resolv.conf"
      if ! ssh $SSH_OPTS ${var.ct_ssh_user}@$CONTROL_IP \
        "python3 -c 'import socket; socket.setdefaulttimeout(2); socket.getaddrinfo(\"packages.ubuntu.com\", 80)' 2>/dev/null"; then
        echo "WARNING: Gateway $CONTROL_GW svarar inte på DNS — faller tillbaka på ${join(", ", var.dns_servers)}"
      fi

      echo "Kopierar ansible SSH-nyckel till control node..."
      scp $SSH_OPTS ${local_sensitive_file.ansible_ssh_private.filename} ${var.ct_ssh_user}@$CONTROL_IP:.ssh/ansible_ed25519
      ssh $SSH_OPTS ${var.ct_ssh_user}@$CONTROL_IP "chmod 600 ~/.ssh/ansible_ed25519"

      echo "Kopierar deploy key till ansible control..."
      scp $SSH_OPTS ${local_sensitive_file.deploy_private_key.filename} ${var.ct_ssh_user}@$CONTROL_IP:.ssh/deploy_ed25519

      echo "Skriver SSH-config på ansible control node..."
      ssh $SSH_OPTS ${var.ct_ssh_user}@$CONTROL_IP \
        "printf 'Host 10.*\n  User ${var.ct_ssh_user}\n  IdentityFile ~/.ssh/ansible_ed25519\n  StrictHostKeyChecking no\n\nHost github.com\n  IdentityFile ~/.ssh/deploy_ed25519\n  StrictHostKeyChecking no\n' > ~/.ssh/config && chmod 600 ~/.ssh/config"

      echo "Installerar Ansible på ansible control node..."
      ssh $SSH_OPTS ${var.ct_ssh_user}@$CONTROL_IP \
        'apt-get update -qq && \
         DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && \
         DEBIAN_FRONTEND=noninteractive apt-get install -y ansible git && \
         ansible --version'

      echo "Klonar repot på ansible control node..."
      ssh $SSH_OPTS ${var.ct_ssh_user}@$CONTROL_IP \
        "git clone git@github.com:${var.github_owner}/autolab.git ~/autolab"
    EOT
  }
}

# ============================================
# 4. Konfigurera target-noder
# ============================================
resource "terraform_data" "configure_targets" {
  depends_on = [
    proxmox_virtual_environment_container.ansible_target,
    terraform_data.bootstrap_control,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      CONTROL_IP="${local.control_ip}"
      CONTROL_SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.terraform_ssh_private.filename}"
      TARGET_SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.ansible_ssh_private.filename}"

      %{ for name, ip in local.target_ips ~}
      TARGET_IP="${ip}"

      echo "Väntar på SSH till $TARGET_IP..."
      until ssh $TARGET_SSH_OPTS ${var.ct_ssh_user}@$TARGET_IP true 2>/dev/null; do sleep 5; done

      echo "Hämtar gateway från $TARGET_IP..."
      TARGET_GW=$(ssh $TARGET_SSH_OPTS ${var.ct_ssh_user}@$TARGET_IP "ip route show default | awk '{print \$3; exit}'")
      echo "Gateway: $TARGET_GW"

      echo "Konfigurerar DNS på $TARGET_IP ($TARGET_GW)..."
      ssh $TARGET_SSH_OPTS ${var.ct_ssh_user}@$TARGET_IP \
        "{ echo 'nameserver $TARGET_GW'; %{ for dns in var.dns_servers ~}echo 'nameserver ${dns}'; %{ endfor ~}} > /etc/resolv.conf"
      if ! ssh $TARGET_SSH_OPTS ${var.ct_ssh_user}@$TARGET_IP \
        "python3 -c 'import socket; socket.setdefaulttimeout(2); socket.getaddrinfo(\"packages.ubuntu.com\", 80)' 2>/dev/null"; then
        echo "WARNING: Gateway $TARGET_GW svarar inte på DNS — faller tillbaka på ${join(", ", var.dns_servers)}"
      fi

      %{ endfor ~}

      echo "Skriver inventory på ansible control node..."
      ssh $CONTROL_SSH_OPTS ${var.ct_ssh_user}@$CONTROL_IP \
        "printf '[targets]\n${join("\\n", [for name, ip in local.target_ips : "${ip} ansible_user=${var.ct_ssh_user} ansible_ssh_private_key_file=~/.ssh/ansible_ed25519"])}\n' > ~/inventory.ini"
    EOT
  }
}
