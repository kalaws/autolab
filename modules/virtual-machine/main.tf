terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.100.0"
    }
  }
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