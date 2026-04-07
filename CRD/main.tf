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
# 1. Slå upp Packer-byggt template
# ============================================
data "proxmox_virtual_environment_vms" "packer_template" {
  node_name = "pve"
  filter {
    name   = "name"
    values = ["ubuntu-jammy-packer"]
  }
}

# ============================================
# 2. Klona till faktiska VM:ar
# ============================================

# WireGuard VPN – har WAN + intern bridge
resource "proxmox_virtual_environment_vm" "crd_vpn" {
  name      = "LAB-CRD-VPN"
  node_name = "pve"
  depends_on = [terraform_data.apply_network_config]

  clone {
    vm_id = data.proxmox_virtual_environment_vms.packer_template.vms[0].vm_id
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

  stop_on_destroy = true

  agent {
    enabled = true
  }
}

# Konfigurera dnsmasq på crd_vpn som DHCP-server för det interna nätet. 
# Krävs för att VM:ar på internt nät ska vara åtkomstbara.
# Delar ut IP (10.10.50.10–100), gateway (10.10.50.1) och DNS automatiskt.
resource "terraform_data" "setup_vpn_gateway" {
  depends_on = [proxmox_virtual_environment_vm.crd_vpn]

  provisioner "local-exec" {
    command = <<-EOT
      VPN_WAN_IP="${proxmox_virtual_environment_vm.crd_vpn.ipv4_addresses[1][0]}"
      echo "Väntar på SSH till crd_vpn ($VPN_WAN_IP)..."
      until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
        ${var.vm_ssh_user}@$VPN_WAN_IP true 2>/dev/null; do sleep 5; done

      echo "Sätter upp DHCP på crd_vpn..."
      ssh -o StrictHostKeyChecking=no -o BatchMode=yes ${var.vm_ssh_user}@$VPN_WAN_IP \
        'printf "interface=eth1\nbind-interfaces\ndhcp-range=10.10.50.10,10.10.50.100,255.255.255.0,24h\ndhcp-option=option:router,10.10.50.1\ndhcp-option=option:dns-server,8.8.8.8,1.1.1.1\n" | sudo tee /etc/dnsmasq.d/crd-internal.conf && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get install -y dnsmasq && \
         sudo systemctl enable --now dnsmasq'
    EOT
  }
}

# Wazuh server
resource "proxmox_virtual_environment_vm" "crd_wazuh" {
  name      = "LAB-CRD-Wazuh"
  node_name = "pve"
  depends_on = [terraform_data.setup_vpn_gateway]

  clone {
    vm_id = data.proxmox_virtual_environment_vms.packer_template.vms[0].vm_id
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
        address = "dhcp"
      }
    }
  }

  stop_on_destroy = true

  agent {
    enabled = true
  }
}

# Field worker laptop
resource "proxmox_virtual_environment_vm" "crd_field_laptop" {
  name      = "LAB-CRD-field-laptop"
  node_name = "pve"

  clone {
    vm_id = data.proxmox_virtual_environment_vms.packer_template.vms[0].vm_id
  }

  memory {
    dedicated = 1024
  }

  network_device {
    bridge = var.bridge_autolab_wan
  }

  # Överskrid cloud-init per VM
  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  stop_on_destroy = true

  agent {
    enabled = true
  }
}

# Sweden office workstation
resource "proxmox_virtual_environment_vm" "crd_office_ws" {
  name      = "LAB-CRD-office-ws"
  node_name = "pve"
  depends_on = [terraform_data.setup_vpn_gateway]

  clone {
    vm_id = data.proxmox_virtual_environment_vms.packer_template.vms[0].vm_id
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
        address = "dhcp"
      }
    }
  }

  stop_on_destroy = true

  agent {
    enabled = true
  }
}
