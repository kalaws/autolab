output "ansible_control_ip" {
  value = try(proxmox_virtual_environment_vm.ansible_control.ipv4_addresses[1][0], "not available yet")
}

output "k8s_control_ip" {
  value = try(proxmox_virtual_environment_vm.k8s_control.ipv4_addresses[1][0], "not available yet")
}

output "k8s_worker_ip" {
  value = try(proxmox_virtual_environment_vm.k8s_worker.ipv4_addresses[1][0], "not available yet")
}
