terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.100.0"
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name      = var.vm_name
  node_name = var.node_name
  vm_id     = var.vm_id

  clone {
    vm_id = var.clone_id
  }

  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory
  }

  agent {
    enabled = true
  }

  network_device {
    bridge = "vnet1"
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      username = "ubuntu"
      keys     = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFkJG0AoEd8MxvxkIA1+7k181xXwCHbdr/jjSm1ofc6E control-node@proxmox"]
    }
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat > ${path.module}/../../ansible/inventory.ini << 'EOF'
[webservers]
${self.name} ansible_host=${self.ipv4_addresses[1][0]}

[webservers:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
    EOT
  }
}