variable "packer_template" {
  type        = list(string)
  description = "Packer template för kubernetes VMs"
  default     = ["ubuntu-2404-q35-template"]
}

variable "ct_template" {
  type        = string
  description = "LXC-template att använda (måste finnas på Proxmox-noden)"
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

variable "resources" {   
  description = "VM configurations for Kubernetes lab"   
  type = map(object({     
    cores  = number    
    memory = number    
    disk   = number  
  }))
  default = {     
    ansible  = { cores = 1, memory = 512, disk = 8 }
    k8s_control  = { cores = 2, memory = 2048,  disk = 20 }          
    k8s_worker  = { cores = 2, memory = 4096, disk = 40 }     
  } 
}

variable "github_owner" {
  type        = string
  description = "GitHub-användarnamn eller organisation"
  default     = "kalaws"
}

variable "bridge_wan" {
  type        = string
  description = "Bridge för WAN-nät"
  default     = "vnet1"
}

variable "dns_servers" {
  type        = list(string)
  description = "DNS-servrar för CT:arna, utöver gateway"
  default     = ["8.8.8.8"]
}

variable "workers" {
  type        = list(string)
  description = "Kubernetes worker nodes"
  default     = ["1"]
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "ssh_user" {
  type        = string
  description = "SSH-användare i CT:arna"
  default     = "root"
}

variable "k8s_ssh_user" {
  type        = string
  description = "SSH-användare i k8s-noderna"
  default     = "ubuntu"
}
