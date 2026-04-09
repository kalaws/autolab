output "ansible_control_ip" {
  value = try(proxmox_virtual_environment_vm.ansible_control.ipv4_addresses[1][0], "not available yet")
}

output "ansible_target_ips" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.ansible_target :
    name => try(vm.ipv4_addresses[1][0], "not available yet")
  }
}
