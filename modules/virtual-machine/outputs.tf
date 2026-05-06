output "ipv4_address" {
  value       = try(proxmox_virtual_environment_vm.vm.ipv4_addresses[1][0], "not available yet")
  description = "VM:ens primära IPv4-adress (index 1 = första icke-loopback)"
}

output "vm_id" {
  value       = proxmox_virtual_environment_vm.vm.vm_id
  description = "Proxmox VM ID"
}
