output "ansible" {
  value = try(proxmox_virtual_environment_container.ansible.ipv4["eth0"], "not available yet")
}

output "k8s_control" {
  value = {
    for name, vm in proxmox_virtual_environment_vm.k8s_control :
    name => try(vm.ipv4_addresses[1][0], "not available yet")
  }
}