variable "bridge_wan" {
  type        = string
  description = "Bridge för WAN-nät"
  default     = "vnet1"
}

variable "vm_ssh_user" {
  type        = string
  description = "SSH-användare inuti VM:arna"
  default     = "ubuntu"
}
