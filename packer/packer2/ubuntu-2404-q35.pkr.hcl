packer {
  required_plugins {
    proxmox = {
      version = "~> 1"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ──────────────────────────────────────────────
# Variabler
# ──────────────────────────────────────────────

variable "proxmox_url" {
  type        = string
  description = "Proxmox API URL (PKR_VAR_proxmox_url)"
}

variable "proxmox_token_id" {
  type        = string
  description = "API-token ID, t.ex. user@realm!tokenid (PKR_VAR_proxmox_token_id)"
}

variable "proxmox_token_secret" {
  type        = string
  sensitive   = true
  description = "API-token secret UUID (PKR_VAR_proxmox_token_secret)"
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "vm_id" {
  type    = string
  default = "9001"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "iso_file" {
  type    = string
  default = "local:iso/ubuntu-24.04.4-live-server-amd64.iso"
}

variable "bridge" {
  type    = string
  default = "vnet1"
}

# ──────────────────────────────────────────────
# Källdefinition
# ──────────────────────────────────────────────

source "proxmox-iso" "ubuntu-2404-q35" {

  # Autentisering via miljövariabler:
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = true

  node = var.proxmox_node

  # ── VM-inställningar ──
  vm_id                = var.vm_id
  vm_name              = "ubuntu-2404-q35-template"
  template_name        = "ubuntu-2404-q35-template"
  template_description = "Ubuntu 24.04 LTS – Q35/OVMF – Packer ${timestamp()}"
  tags                 = "ubuntu-24_04;template;packer;uefi"
  os                   = "l26"
  qemu_agent           = true

  # ── Q35 maskintyp + OVMF (UEFI) ──
  machine  = "q35"
  bios     = "ovmf"

  efi_config {
    efi_storage_pool  = var.storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  # ── Boot ISO (Ubuntu installer) ──
  boot_iso {
    type             = "scsi"
    iso_file         = var.iso_file
    iso_storage_pool = "local"
    unmount          = true
  }

  # ── Autoinstall via CD (cloud-init CIDATA-volym) ──
  additional_iso_files {
    type             = "sata"
    iso_storage_pool = "local"
    cd_files         = [
      "./files/user-data",
      "./files/meta-data"
    ]
    cd_label = "cidata"
    unmount  = true
  }

  # ── CPU / Minne ──
  cpu_type = "host"
  cores    = 1
  sockets  = 1
  memory   = 1024

  # ── Lagring ──
  scsi_controller = "virtio-scsi-pci"

  disks {
    disk_size    = "20G"
    storage_pool = var.storage_pool
    type         = "virtio"
    format       = "raw"
  }

  # ── Nätverk ──
  network_adapters {
    model    = "virtio"
    bridge   = var.bridge
    firewall = false
  }

  # ── Cloud-init drive (för Terraform-kloning senare) ──
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  # ── Boot-kommando ──
  # Ubuntu 24.04 med OVMF startar via GRUB EFI – samma escape-sekvens gäller.
  boot_wait = "10s"
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud ---<wait>",
    "<f10><wait>"
  ]

  # ── SSH (Packer → gäst-VM, INTE mot Proxmox-noden) ──
  ssh_username           = "ubuntu"
  ssh_private_key_file   = pathexpand("~/.ssh/id_ed25519")
  ssh_timeout            = "20m"
  ssh_pty                = true
  ssh_handshake_attempts = 30
}

# ──────────────────────────────────────────────
# Build
# ──────────────────────────────────────────────

build {
  name = "ubuntu-2404-q35"

  sources = ["source.proxmox-iso.ubuntu-2404-q35"]

  # Vänta på att cloud-init är klart
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Väntar på cloud-init...'; sleep 3; done"
    ]
  }

  # Minimal rensning
  provisioner "shell" {
    inline = [
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
      "sudo rm -f /etc/netplan/*.yaml",
      "sudo cloud-init clean --logs",
      "sudo sync"
    ]
  }

  # Sätt cloud-init datasource till NoCloud (Proxmox-kompatibelt)
  provisioner "file" {
    source      = "./files/99-pve.cfg"
    destination = "/tmp/99-pve.cfg"
  }

  provisioner "shell" {
    inline = [
      "sudo cp /tmp/99-pve.cfg /etc/cloud/cloud.cfg.d/99-pve.cfg"
    ]
  }
}
