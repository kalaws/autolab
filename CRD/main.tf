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

# WireGuard VPN – har WAN + intern bridge och agerar NAT-gateway för det interna nätet
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

  stop_on_destroy = true

  agent {
    enabled = true
  }
}

# Konfigurera crd_vpn som NAT-gateway och DHCP-server för det interna nätet.
# dnsmasq delar ut IP (10.10.50.10–100), gateway (10.10.50.1) och DNS automatiskt,
# vilket gör att cloud-init på interna VM:ar kan installera qemu-guest-agent.
resource "terraform_data" "setup_vpn_gateway" {
  depends_on = [proxmox_virtual_environment_vm.crd_vpn]

  provisioner "local-exec" {
    command = <<-EOT
      VPN_WAN_IP="${proxmox_virtual_environment_vm.crd_vpn.ipv4_addresses[1][0]}"
      echo "Väntar på SSH till crd_vpn ($VPN_WAN_IP)..."
      until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes \
        ${var.vm_ssh_user}@$VPN_WAN_IP true 2>/dev/null; do sleep 5; done

      echo "Sätter upp NAT + DHCP på crd_vpn..."
      ssh -o StrictHostKeyChecking=no -o BatchMode=yes ${var.vm_ssh_user}@$VPN_WAN_IP \
        'WAN_IF=$(ip route | awk "/default/ {print \$5; exit}") && \
         sudo sysctl -w net.ipv4.ip_forward=1 && \
         grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf && \
         sudo iptables -t nat -C POSTROUTING -s 10.10.50.0/24 -o $WAN_IF -j MASQUERADE 2>/dev/null || \
           sudo iptables -t nat -A POSTROUTING -s 10.10.50.0/24 -o $WAN_IF -j MASQUERADE && \
         echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | sudo debconf-set-selections && \
         echo "iptables-persistent iptables-persistent/autosave_v6 boolean false" | sudo debconf-set-selections && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent dnsmasq && \
         sudo netfilter-persistent save && \
         printf "interface=eth1\nbind-interfaces\ndhcp-range=10.10.50.10,10.10.50.100,255.255.255.0,24h\ndhcp-option=option:router,10.10.50.1\ndhcp-option=option:dns-server,8.8.8.8,1.1.1.1\n" | sudo tee /etc/dnsmasq.d/crd-internal.conf && \
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
        address = "dhcp"
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
        address = "dhcp"
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
