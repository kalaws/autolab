variable "vm_id" {
    description = "ID för VMen i Proxmox"
    type = number
}

variable "vm_name" {
    description = "Namnet på VMen"
    type = string
}

variable "cpu_cores" {
    description = "Antal CPU-kärnor"
    type = number  
}

variable "memory" {
    description = "RAM i MB"
    type = number
}