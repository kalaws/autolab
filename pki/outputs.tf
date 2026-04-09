output "control_ip" {
  value = try(proxmox_virtual_environment_vm.control.ipv4_addresses[1][0], "not available yet")
}

output "ca_ip" {
  value = try(proxmox_virtual_environment_vm.ca.ipv4_addresses[1][0], "not available yet")
}

output "server_ip" {
  value = try(proxmox_virtual_environment_vm.server.ipv4_addresses[1][0], "not available yet")
}

output "client_ip" {
  value = try(proxmox_virtual_environment_vm.client.ipv4_addresses[1][0], "not available yet")
}
