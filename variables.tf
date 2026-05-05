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
  description = "VM/CT configurations for Kubernetes lab"   
  default = {     
    ansible  = { hostname = "LAB-K8S-ansible", cores = 1, memory = 512, disk = 8 }
    k8s_control  = { hostname = "LAB-K8S-master", cores = 2, memory = 4096,  disk = 20 }          
    k8s_worker  = { hostname = "LAB-K8S-worker", cores = 2, memory = 4096, disk = 40 }
  } 
  type = map(object({  
    hostname = string   
    cores    = number    
    memory   = number    
    disk     = number  
  }))
}