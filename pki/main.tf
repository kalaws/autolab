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

# SSH-nyckelpar för control → noder
resource "tls_private_key" "control" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "control_private_key" {
  content         = tls_private_key.control.private_key_openssh
  filename        = "${path.module}/.control_ed25519"
  file_permission = "0600"
}

resource "local_file" "control_public_key" {
  content         = tls_private_key.control.public_key_openssh
  filename        = "${path.module}/.control_ed25519.pub"
  file_permission = "0644"
}

# Deploy key för git clone
resource "tls_private_key" "deploy_key" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "deploy_private_key" {
  content         = tls_private_key.deploy_key.private_key_openssh
  filename        = "${path.module}/.deploy_ed25519"
  file_permission = "0600"
}

resource "github_repository_deploy_key" "autolab" {
  title      = "LAB-PKI-control"
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

locals {
  vm_template_id = data.proxmox_virtual_environment_vms.packer_template.vms[0].vm_id

  vms = {
    control = { memory = 2048 }
    ca      = { memory = 1024 }
    server  = { memory = 1024 }
    client  = { memory = 1024 }
  }
}

resource "proxmox_virtual_environment_vm" "control" {
  name      = "LAB-PKI-control"
  node_name = "pve"
  clone { vm_id = local.vm_template_id }
  memory { dedicated = local.vms.control.memory }
  network_device { bridge = var.bridge_wan }
  initialization { ip_config { ipv4 { address = "dhcp" } } }
  stop_on_destroy = true
  agent { enabled = true }
}

resource "proxmox_virtual_environment_vm" "ca" {
  name      = "LAB-PKI-ca"
  node_name = "pve"
  clone { vm_id = local.vm_template_id }
  memory { dedicated = local.vms.ca.memory }
  network_device { bridge = var.bridge_wan }
  initialization { ip_config { ipv4 { address = "dhcp" } } }
  stop_on_destroy = true
  agent { enabled = true }
}

resource "proxmox_virtual_environment_vm" "server" {
  name      = "LAB-PKI-server"
  node_name = "pve"
  clone { vm_id = local.vm_template_id }
  memory { dedicated = local.vms.server.memory }
  network_device { bridge = var.bridge_wan }
  initialization { ip_config { ipv4 { address = "dhcp" } } }
  stop_on_destroy = true
  agent { enabled = true }
}

resource "proxmox_virtual_environment_vm" "client" {
  name      = "LAB-PKI-client"
  node_name = "pve"
  clone { vm_id = local.vm_template_id }
  memory { dedicated = local.vms.client.memory }
  network_device { bridge = var.bridge_wan }
  initialization { ip_config { ipv4 { address = "dhcp" } } }
  stop_on_destroy = true
  agent { enabled = true }
}

# ============================================
# 3. Provisioning
# ============================================
resource "terraform_data" "setup" {
  depends_on = [
    proxmox_virtual_environment_vm.control,
    proxmox_virtual_environment_vm.ca,
    proxmox_virtual_environment_vm.server,
    proxmox_virtual_environment_vm.client,
    github_repository_deploy_key.autolab,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      CONTROL_IP="${proxmox_virtual_environment_vm.control.ipv4_addresses[1][0]}"
      CA_IP="${proxmox_virtual_environment_vm.ca.ipv4_addresses[1][0]}"
      SERVER_IP="${proxmox_virtual_environment_vm.server.ipv4_addresses[1][0]}"
      CLIENT_IP="${proxmox_virtual_environment_vm.client.ipv4_addresses[1][0]}"
      SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes"
      USER="${var.vm_ssh_user}"

      echo "Väntar på SSH till alla noder..."
      for IP in $CONTROL_IP $CA_IP $SERVER_IP $CLIENT_IP; do
        until ssh $SSH_OPTS $USER@$IP true 2>/dev/null; do sleep 5; done
        echo "  $IP redo"
      done

      echo "Lägger till control nodes pubkey på alla noder..."
      for IP in $CA_IP $SERVER_IP $CLIENT_IP; do
        ssh-copy-id $SSH_OPTS -i ${local_file.control_public_key.filename} $USER@$IP
      done

      echo "Kopierar SSH-nycklar till control node..."
      scp $SSH_OPTS ${local_sensitive_file.control_private_key.filename} $USER@$CONTROL_IP:.ssh/control_ed25519
      scp $SSH_OPTS ${local_sensitive_file.deploy_private_key.filename} $USER@$CONTROL_IP:.ssh/deploy_ed25519

      echo "Skriver SSH-config på control node..."
      ssh $SSH_OPTS $USER@$CONTROL_IP \
        "printf 'Host 10.*\n  User $USER\n  IdentityFile ~/.ssh/control_ed25519\n  StrictHostKeyChecking no\n\nHost github.com\n  IdentityFile ~/.ssh/deploy_ed25519\n  StrictHostKeyChecking no\n' > ~/.ssh/config && chmod 600 ~/.ssh/config"

      echo "Skriver inventory på control node..."
      ssh $SSH_OPTS $USER@$CONTROL_IP "cat > ~/inventory.ini" <<INVENTORY
[ca]
$CA_IP ansible_user=$USER ansible_ssh_private_key_file=~/.ssh/control_ed25519

[servers]
$SERVER_IP ansible_user=$USER ansible_ssh_private_key_file=~/.ssh/control_ed25519

[clients]
$CLIENT_IP ansible_user=$USER ansible_ssh_private_key_file=~/.ssh/control_ed25519
INVENTORY

      echo "Installerar Ansible på control node..."
      ssh $SSH_OPTS $USER@$CONTROL_IP \
        'sudo cloud-init status --wait && \
         sudo apt-get -o DPkg::Lock::Timeout=300 update -qq && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y ansible git && \
         ansible-galaxy collection install community.crypto'

      echo "Klonar repot på control node..."
      ssh $SSH_OPTS $USER@$CONTROL_IP \
        "git clone -b ${var.github_branch} git@github.com:${var.github_owner}/autolab.git ~/autolab"

      echo "Kör playbooks..."
      ssh $SSH_OPTS $USER@$CONTROL_IP \
        "ansible-playbook -i ~/inventory.ini ~/autolab/pki/playbooks/site.yml"
    EOT
  }
}
