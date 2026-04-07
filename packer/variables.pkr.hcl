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

variable "base_template_id" {
  type        = number
  description = "VM-ID för base-templaten att klona från"
}

variable "bridge_wan" {
  type        = string
  description = "WAN-bridge"
  default     = "vnet1"
}

variable "ssh_user" {
  type        = string
  description = "SSH-användare i VM:en"
  default     = "ubuntu"
}

variable "ssh_private_key_file" {
  type        = string
  description = "Sökväg till SSH-privat nyckel"
  default     = "~/.ssh/id_rsa"
}
