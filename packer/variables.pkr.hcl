# ──────────────────────────────────────────────
# Variables
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
