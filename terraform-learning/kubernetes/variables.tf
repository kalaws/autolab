variable "control_plane_id" {
    description = "VM ID för control plane noden"
    type = number
}

variable "control_plane_name" {
    description = "Namn på control plane noden"
    type = string
}

variable "worker_count" {
    description = "Antal woker noder"
    type = number
}

variable "worker_id_start" {
    description = "Start ID för wokrer noderna"
    type = number
}

variable "cpu_cores" {
    description = "Antal CPU-kärnor per nod"
    type = number
}

variable "memory" {
    description = "RAM i MB per nod"
    type = number
}

variable "clone_id" {
    description = "ID på templaten att klona från"
    type = number
}

variable "node_name" {
    description = "Namnet på proxmox-noden"
    type = string
}