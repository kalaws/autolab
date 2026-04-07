terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.99.0" # Using the required version
    }
  }
}
# Provider is configured using environment args
provider "proxmox" {}

# ============================================
# 0. Skapa internal network bridge
# ============================================
resource "proxmox_virtual_environment_network_linux_bridge" "crd_internal" {
  node_name = "pve"
  name      = "crdbr0"
  comment   = "CRD Lab - Internal network"
  autostart = true
}

# Proxmox kräver att nätverkskonfigurationen tillämpas efter att en bridge
# skapats, annars är den inte aktiv. Motsvarar "Apply Configuration" i UI:t.
resource "terraform_data" "apply_network_config" {
  depends_on = [proxmox_virtual_environment_network_linux_bridge.crd_internal]

  provisioner "local-exec" {
    command = "curl -k -X PUT \"$PROXMOX_VE_ENDPOINT/api2/json/nodes/pve/network\" -H \"Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN\""
  }
}

# ============================================
# 1. Ladda ner Ubuntu Jammy cloud image
# ============================================
#resource "proxmox_virtual_environment_download_file" "ubuntu_jammy" {
#  content_type = "import"
#  datastore_id = "local"
#  node_name    = "pve"
#  url          = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
#  file_name    = "jammy-server-cloudimg-amd64.qcow2"
#  overwrite    = true
#}

# ============================================
# 2. Skapa template från cloud image
# ============================================
resource "proxmox_virtual_environment_vm" "ubuntu_jammy_template" {
  name      = "ubuntu-jammy-template"
  node_name = "pve"
  template  = true
  started   = false

  cpu {
    cores = 1
  }

  memory {
    dedicated = 1024
  }

  disk {
    datastore_id = "local-lvm"
    import_from  = "local:import/jammy-server-cloudimg-amd64.qcow2"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 10
  }

  network_device {
    bridge = var.bridge_autolab_wan
  }

  # Cloud-init: krävs för att kunna logga in
  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  # Krävs för att QEMU guest agent ska fungera
  agent {
    enabled = true
  }

  serial_device {}
}

# ============================================
# 3. Klona till faktiska VM:ar
# ============================================

# WireGuard VPN
resource "proxmox_virtual_environment_vm" "crd_vpn" {
  name      = "LAB-CRD-VPN"
  node_name = "pve"
  depends_on = [terraform_data.apply_network_config]

  clone {
    vm_id = proxmox_virtual_environment_vm.ubuntu_jammy_template.id
  }

  memory {
    dedicated = 512
  }

  network_device {
    bridge = var.bridge_autolab_wan
  }

  network_device {
    bridge = proxmox_virtual_environment_network_linux_bridge.crd_internal.name   # Internal LAN
  }

  # Överskrid cloud-init per VM
  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    ip_config {
      ipv4 {
        address = "10.10.50.1/24"
      }
    }

    #user account konfigureras i lokal fil på Proxmox-host (/var/lib/vz/snippets/cloud-config.yaml) 
    user_data_file_id = "local:snippets/cloud-config.yaml"
  }

  agent {
    enabled = true
  }
}

# Wazuh server
resource "proxmox_virtual_environment_vm" "crd_wazuh" {
  name      = "LAB-CRD-Wazuh"
  node_name = "pve"
  depends_on = [terraform_data.apply_network_config]
  clone {
    vm_id = proxmox_virtual_environment_vm.ubuntu_jammy_template.id
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = 30
  }

  network_device {
    bridge = proxmox_virtual_environment_network_linux_bridge.crd_internal.name   # Internal LAN
  }

  # Överskrid cloud-init per VM
  initialization {
    ip_config {
      ipv4 {
        address = "10.10.50.2/24"
        gateway = "10.10.50.1"
      }
    }

    #user account konfigureras i lokal fil på Proxmox-host (/var/lib/vz/snippets/cloud-config.yaml)
    user_data_file_id = "local:snippets/cloud-config.yaml"
  }

  agent {
    enabled = true
  }

}



# Field worker laptop
resource "proxmox_virtual_environment_vm" "crd_field_laptop" {
  name      = "LAB-CRD-field-laptop"
  node_name = "pve"

  clone {
    vm_id = proxmox_virtual_environment_vm.ubuntu_jammy_template.id
  }

  memory {
    dedicated = 1024
  }

  # Överskrid cloud-init per VM
  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    #user account konfigureras i lokal fil på Proxmox-host (/var/lib/vz/snippets/cloud-config.yaml) 
    user_data_file_id = "local:snippets/cloud-config.yaml"
  }

  agent {
    enabled = true
  }

}


# Sweden office workstation
resource "proxmox_virtual_environment_vm" "crd_office_ws" {
  name      = "LAB-CRD-office-ws"
  node_name = "pve"
  depends_on = [terraform_data.apply_network_config]
  clone {
    vm_id = proxmox_virtual_environment_vm.ubuntu_jammy_template.id
  }

  memory {
    dedicated = 1024
  }


  network_device {
    bridge = proxmox_virtual_environment_network_linux_bridge.crd_internal.name  # Internal LAN
  }  

  # Överskrid cloud-init per VM
  initialization {
    ip_config {
      ipv4 {
        address = "10.10.50.3/24"
        gateway = "10.10.50.1"
      }
    }

    #user account konfigureras i lokal fil på Proxmox-host (/var/lib/vz/snippets/cloud-config.yaml) 
    user_data_file_id = "local:snippets/cloud-config.yaml"
  }

  agent {
    enabled = true
  }

}