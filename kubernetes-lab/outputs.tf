output "ansible_ip" {
  value = try(proxmox_virtual_environment_container.ansible.network_interface[0].ip_address, "not available yet")
}

output "k8s_control_ip" {
  value = try(proxmox_virtual_environment_vm.k8s_control["LAB-K8S-control"].ipv4_addresses[1][0], "not available yet")
}