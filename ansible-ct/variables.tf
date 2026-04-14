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

variable "targets" {
  type        = list(string)
  description = "Namn på target-CT:ar"
  default     = ["target-1"]
}