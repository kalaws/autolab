terraform {
    required_providers {
      proxmox = {
        source = "bpg/proxmox"
        version = "~> 0.73"
      }
    }
}


provider "proxmox" {
    endpoint = "https://100.123.44.38:8006"
    username = "admin"
    password = "admin"
    insecure = true
}