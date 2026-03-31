variable "virtual_environment_api_token" {
  type = string
  description = "Terraform Proxmox API token"
  sensitive = true
}

variable "virtual_environment_endpoint" {
  type = string
  description = "Proxmox API endpoint"
  sensitive = true
}