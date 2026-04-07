packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = "~> 1"
    }
  }
}

# Klonar från den Terraform-skapade base-templaten och installerar
# qemu-guest-agent så att alla framtida kloner har den inbakad.
source "proxmox-clone" "ubuntu_jammy" {
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_token_id
  token                    = var.proxmox_token_secret
  insecure_skip_tls_verify = true
  node                     = "pve"

  clone_vm_id = var.base_template_id
  vm_name     = "ubuntu-jammy-base"

  # Starta på WAN-bridge så Packer kan nå VM:en via SSH
  network_adapters {
    bridge = var.bridge_wan
  }

  # Cloud-init kör automatiskt och sätter upp SSH
  ssh_username        = var.ssh_user
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout         = "5m"

  template_name        = "ubuntu-jammy-packer"
  template_description = "Ubuntu Jammy med qemu-guest-agent – byggd av Packer"
}

build {
  sources = ["source.proxmox-clone.ubuntu_jammy"]

  provisioner "shell" {
    inline = [
      "sudo apt-get install -y qemu-guest-agent",
      "sudo systemctl enable qemu-guest-agent",
      # Rensa cloud-init state så det körs om vid nästa boot (kloning)
      "sudo cloud-init clean",
    ]
  }
}
