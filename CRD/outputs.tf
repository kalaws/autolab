output "crd_vpn_ip" {
  value = try(proxmox_virtual_environment_vm.crd_vpn.ipv4_addresses[1][0], "not available yet")
}

output "crd_wazuh_ip" {
  value = try(proxmox_virtual_environment_vm.crd_wazuh.ipv4_addresses[1][0], "not available yet")
}

output "crd_field_ip" {
  value = try(proxmox_virtual_environment_vm.crd_field_laptop.ipv4_addresses[1][0], "not available yet")
}

output "crd_office_ip" {
  value = try(proxmox_virtual_environment_vm.crd_office_ws.ipv4_addresses[1][0], "not available yet")
}