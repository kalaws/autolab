output "ansible_ssh_pubkey" {
  value     = tls_private_key.ansible_ssh.public_key_openssh
  sensitive = false
}

output "ansible" {
  value = try(proxmox_virtual_environment_container.ansible.ipv4["eth0"], "not available yet")
}

output "k8s_control" {
  value = try(proxmox_virtual_environment_vm.k8s_control.ipv4_addresses[1][0], "not available yet")
}

output "k8s_workers" {
  value = [
    for vm in proxmox_virtual_environment_vm.k8s_worker :
    try(vm.ipv4_addresses[1][0], "not available yet")
  ]
}
