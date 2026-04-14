variable "ct_ssh_user" {
  type        = string
  description = "SSH-användare i CT:arna"
  default     = "root"
}

variable "github_owner" {
  type        = string
  description = "GitHub-användarnamn eller organisation"
  default     = "kalaws"
}

variable "ct_template" {
  type        = string
  description = "LXC-template att använda (måste finnas på Proxmox-noden)"
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "bridge_wan" {
  type        = string
  description = "Bridge för WAN-nät"
  default     = "vnet1"
}

variable "ct_disk_storage" {
  type        = string
  description = "Datastore för CT-diskar"
  default     = "local-lvm"
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS-servrar för CT:arna, utöver gateway"
  default     = ["8.8.8.8"]
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "targets" {
  type        = list(string)
  description = "Namn på target-CT:ar"
  default     = ["target-1"]
}