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
  }
}

provider "proxmox" {}

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