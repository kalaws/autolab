output "control_plane_id" {
    description = "IP-adressen för control plane"
    value = module.control_plane.vm_ip  
}

output "woker_ips" {
    description = "IP-adresser för woker noderna"
    value = module.workers[*].vm_ip
}