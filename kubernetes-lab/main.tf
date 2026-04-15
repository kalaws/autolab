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
# 1. Slå upp Packer-byggt template
# ============================================
data "proxmox_virtual_environment_vms" "packer_template" {
  node_name = "pve"
  filter {
    name   = "name"
    values = var.packer_template
  }
}

# ============================================
# 2. Klona Ansible control node CT
# ============================================
resource "proxmox_virtual_environment_container" "ansible" {
  description = "Ansible control node (CT)"
  node_name   = "pve"
  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = "LAB-K8S-ansible"

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

  memory {
    dedicated = var.resources["ansible"].memory
  }

  cpu {
    cores = var.resources["ansible"].cores
  }
  
  disk {
    datastore_id = "local-lvm"     
    size         = var.resources["ansible"].disk  
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge_wan
  }

  operating_system {
    template_file_id = var.ct_template
    type             = "ubuntu"
  }

  started = true
}

locals {
  control_ip = proxmox_virtual_environment_container.ansible.ipv4["eth0"]
  target_ips = {
    for name, vm in proxmox_virtual_environment_vm.k8s_control :
    name => vm.ipv4_addresses[1]
  }
}

# ============================================
# 3. Bootstrappa control node
# ============================================
resource "terraform_data" "bootstrap_control" {
  depends_on = [
    proxmox_virtual_environment_container.ansible,
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
# 4. Klona Kubernetes control node VM
# ============================================
resource "proxmox_virtual_environment_vm" "k8s_control" {
  for_each  = toset(var.targets)
  name      = "LAB-K8S-control"
  node_name = "pve"

  clone {
    vm_id = data.proxmox_virtual_environment_vms.packer_template.vms[0].vm_id
  }

  memory {
    dedicated = var.resources["k8s_control"].memory
  }

  cpu {
    cores = var.resources["k8s_control"].cores
  }
  
  disk {
    datastore_id = "local-lvm"     
    interface    = "virtio0"     
    iothread     = true     
    discard      = "on"     
    size         = var.resources["k8s_control"].disk  
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
# 5. Klona Kubernetes worker nodes VM
# ============================================
resource "proxmox_virtual_environment_vm" "k8s_worker" {
  for_each  = toset(var.workers)
  name      = "LAB-K8S-worker-${each.key}"
  node_name = "pve"

  clone {
    vm_id = data.proxmox_virtual_environment_vms.packer_template.vms[0].vm_id
  }

  memory {
    dedicated = var.resources["k8s_worker"].memory
  }

  cpu {
    cores = var.resources["k8s_worker"].cores
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.resources["k8s_worker"].disk
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
    user_account {
      keys = [trimspace(tls_private_key.ansible_ssh.public_key_openssh)]
    }
  }

  stop_on_destroy = true

  agent {
    enabled = true
  }
}