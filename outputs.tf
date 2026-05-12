output "ansible" {
  value = try(module.ansible.ipv4_address, "not available yet")
}

output "vault" {
  value = try(module.vault.ipv4_address, "not available yet")
}

output "k8s_control" {
  value = try(module.k8s_control.ipv4_address, "not available yet")
}

output "k8s_workers" {
  value = [
    for vm in module.k8s_worker :
    try(vm.ipv4_address, "not available yet")
  ]
}