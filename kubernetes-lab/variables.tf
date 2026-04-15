variable "packer_template" {
  type        = list(string)
  description = "Packer template för kubernetes VMs"
  default     = ["ubuntu-2404-q35-template"]
}

variable "resources" {   
  description = "VM configurations for Kubernetes lab"   
  type = map(object({     
    cores  = number    
    memory = number    
    disk   = number  
  }))
  default = {     
    ansible  = { cores = 1, memory = 1024, disk = 8 }
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

variable "ct_template" {
  type        = string
  description = "LXC-template att använda (måste finnas på Proxmox-noden)"
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}