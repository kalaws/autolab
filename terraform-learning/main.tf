terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.100.0"
    }
  }
}

provider "proxmox" {}

module "learning_vm" {
  source = "./modules/virtual-machine"

  vm_id     = var.vm_id
  vm_name   = var.vm_name
  cpu_cores = var.cpu_cores
  memory    = var.memory
  clone_id  = 116
  node_name = "pve"
}