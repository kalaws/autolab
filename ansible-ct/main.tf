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

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [trimspace(tls_private_key.terraform_ssh.public_key_openssh)]
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

locals {
  control_ip = proxmox_virtual_environment_container.ansible_control.ipv4["eth0"]
}
