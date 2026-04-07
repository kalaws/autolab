variable "bridge_autolab_wan" {
  type = string
  description = "Bridge for autolab subnet"
  sensitive = false
  default = "vnet1"
}

