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
