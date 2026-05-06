terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.100.0"
    }
  }
}

resource "proxmox_virtual_environment_container" "ct" {
  node_name    = var.node_name
  unprivileged = var.unprivileged

  features {
    nesting = var.nesting
  }

  initialization {
    hostname = var.ct_name

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = var.ssh_keys
    }
  }

  memory {
    dedicated = var.memory
  }

  cpu {
    cores = var.cpu_cores
  }

  disk {
    datastore_id = "local-lvm"
    size         = var.disk
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
