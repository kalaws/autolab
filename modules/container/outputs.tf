output "ipv4_address" {
  value       = proxmox_virtual_environment_container.ct.ipv4["eth0"]
  description = "CT:ns IPv4-adress (eth0)"
}

output "vm_id" {
  value       = proxmox_virtual_environment_container.ct.vm_id
  description = "Proxmox CT ID"
}
