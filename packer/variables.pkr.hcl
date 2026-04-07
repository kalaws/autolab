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

variable "iso_file" {
  type        = string
  description = "ISO-fil i Proxmox storage, t.ex. local:iso/ubuntu-22.04.5-live-server-amd64.iso (PKR_VAR_iso_file)"
  default     = "local:iso/ubuntu-24.04.4-live-server-amd64.iso"
}

variable "ssh_public_key_file" {
  type        = string
  description = "Sökväg till SSH-publik nyckel (PKR_VAR_ssh_public_key_file)"
  default     = "~/.ssh/id_ed25519.pub"
}

variable "bridge_wan" {
  type        = string
  description = "WAN-bridge"
  default     = "vnet1"
}
