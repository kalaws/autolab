variable "bridge_autolab_wan" {
  type        = string
  description = "Bridge for autolab subnet"
  sensitive   = false
  default     = "vnet1"
}

variable "vm_ssh_user" {
  type        = string
  description = "SSH-användare inuti VM:arna (satt i cloud-config.yaml)"
  default     = "ubuntu"
}
