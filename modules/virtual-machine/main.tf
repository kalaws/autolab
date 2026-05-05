data "proxmox_virtual_environment_vms" "packer_template" {
  node_name = var.node_name
  filter {
    name   = "name"
    values = var.packer_template
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name      = var.vm_name
  node_name = var.node_name

  clone {
    vm_id = data.proxmox_virtual_environment_vms.packer_template.vms[0].vm_id
  }

  memory {
    dedicated = var.memory
  }

  cpu {
    cores = var.cpu_cores
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.disk
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
      username = var.ansible_user
      keys     = [var.ansible_ssh_public_key]
    }
  }

  stop_on_destroy = true

  agent {
    enabled = true
  }
}
