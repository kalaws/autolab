variable "vm_name" {
  type        = string
  description = "Namn på VM:en"
}

variable "node_name" {
  type        = string
  description = "Proxmox-nod att deploya på"
  default     = "pve"
}

variable "packer_template" {
  type        = list(string)
  description = "Packer template att klona"
  default     = ["ubuntu-2404-q35-template"]
}

variable "memory" {
  type        = number
  description = "RAM i MB"
}

variable "cpu_cores" {
  type        = number
  description = "Antal CPU-cores"
}

variable "disk" {
  type        = number
  description = "Diskstorlek i GB"
}

variable "bridge_wan" {
  type        = string
  description = "Bridge för nätverksinterface"
}

variable "ansible_user" {
  type        = string
  description = "Maskinanvändare som används av Ansible"
  default     = "ansible"
}

variable "ansible_ssh_public_key" {
  type        = string
  description = "Publik SSH-nyckel för ansible-användaren (injiceras vid cloud-init)"
}
