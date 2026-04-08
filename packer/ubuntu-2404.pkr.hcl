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

variable "proxmox_node" {
  type    = string
  default = "pve"
}

#variable "vm_id" {
#  type    = number
#  default = 9000
#}

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
# Lokala värden
# ──────────────────────────────────────────────

locals {
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))
  build_time     = timestamp()
}

# ──────────────────────────────────────────────
# Källdefinition
# ──────────────────────────────────────────────

source "proxmox-iso" "ubuntu-2404" {

  # Autentisering hämtas från miljövariabler:
  #   PROXMOX_URL       = "https://<ip>:8006/api2/json"
  #   PROXMOX_USERNAME  = "user@realm!tokenid"
  #   PROXMOX_TOKEN     = "<token-secret>"
  insecure_skip_tls_verify = true

  node = var.proxmox_node

  # ── VM-inställningar ──
  vm_id                = var.vm_id
  vm_name              = "ubuntu-2404-template"
  template_name        = "ubuntu-2404-template"
  template_description = "Ubuntu 24.04 LTS – skapad av Packer ${local.build_time}"
  tags                 = "ubuntu-24.04;template;packer"
  os                   = "l26"
  machine              = "q35"
  bios                 = "ovmf"
  qemu_agent           = true

  efi_config {
    efi_storage_pool  = var.storage_pool
    pre_enrolled_keys = true
    efi_type          = "4m"
  }

  # ── ISO ──
  boot_iso {
    type             = "scsi"
    iso_file         = var.iso_file
    iso_storage_pool = "local"
    unmount          = true
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
    discard      = true
    ssd          = true
  }

  # ── Nätverk ──
  network_adapters {
    model    = "virtio"
    bridge   = var.bridge
    firewall = false
  }

  # ── Cloud-init (Terraform kan använda detta senare) ──
  cloud_init              = true
  cloud_init_storage_pool = var.storage_pool

  # ── Autoinstall via CD (inline cloud-init) ──
  # Packer skapar en liten ISO med dessa filer och monterar den.
  # Ubuntu autoinstall hittar CIDATA-volymen automatiskt.
  cd_content = {
    "meta-data" = ""
    "user-data" = templatefile("${path.root}/user-data.pkrtpl.hcl", {
      ssh_public_key = local.ssh_public_key
    })
  }
  cd_label = "cidata"

  # ── Boot-kommando ──
  # Ubuntu 24.04 GRUB: tryck 'e' för att redigera, navigera till
  # kernel-raden, lägg till autoinstall, tryck F10 för att boota.
  boot_wait = "10s"
  boot_command = [
    "<wait>e<wait3>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud",
    "<f10>"
  ]

  # ── SSH-anslutning (Packer → VM under provisionering) ──
  ssh_username         = "ubuntu"
  ssh_private_key_file = pathexpand("~/.ssh/id_ed25519")
  ssh_timeout          = "20m"
  ssh_pty              = true
  ssh_handshake_attempts = 30
}

# ──────────────────────────────────────────────
# Build
# ──────────────────────────────────────────────

build {
  name = "ubuntu-2404"

  sources = ["source.proxmox-iso.ubuntu-2404"]

  # Vänta på att cloud-init är helt klart
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Väntar på cloud-init...'; sleep 3; done"
    ]
  }

  # Uppdatera och installera baspaket
  provisioner "shell" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get upgrade -y",
      "sudo apt-get install -y qemu-guest-agent cloud-init openssh-server curl wget gnupg software-properties-common",
      "sudo systemctl enable qemu-guest-agent"
    ]
  }

  # Rensa för template
  provisioner "shell" {
    inline = [
      # Rensa apt-cache
      "sudo apt-get autoremove -y",
      "sudo apt-get clean",

      # Rensa cloud-init så det körs igen vid kloning
      "sudo cloud-init clean --logs --seed",

      # Rensa maskin-ID (genereras vid nästa boot)
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",

      # Rensa SSH host-nycklar (genereras vid nästa boot)
      "sudo rm -f /etc/ssh/ssh_host_*",

      # Nollställ nätverk
      "sudo rm -f /etc/netplan/*.yaml",

      # Rensa tmp och loggar
      "sudo rm -rf /tmp/* /var/tmp/*",
      "sudo find /var/log -type f -exec truncate -s 0 {} \\;",

      # Rensa bash-historik
      "rm -f ~/.bash_history",
      "history -c",

      # Synka disk
      "sync"
    ]
  }
}
