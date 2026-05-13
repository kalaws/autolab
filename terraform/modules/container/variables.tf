variable "ct_name" {
  type        = string
  description = "Hostname för CT:n"
}

variable "node_name" {
  type        = string
  description = "Proxmox-nod att deploya på"
  default     = "pve"
}

variable "ct_template" {
  type        = string
  description = "LXC-template att använda (måste finnas på Proxmox-noden)"
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

variable "dns_servers" {
  type        = list(string)
  description = "DNS-servrar"
  default     = ["8.8.8.8"]
}

variable "ssh_keys" {
  type        = list(string)
  description = "Publika SSH-nycklar för root-kontot"
}

variable "unprivileged" {
  type        = bool
  description = "Kör CT:n som oprivilegerad"
  default     = true
}

variable "nesting" {
  type        = bool
  description = "Aktivera nesting (behövs för Docker i CT)"
  default     = false
}
