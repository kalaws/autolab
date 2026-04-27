output "vm_ids" {
    description = "IDs för den skapade VMar"
    value       = proxmox_virtual_environment_vm.learning_vm[*].vm_id
}

output "vm_name" {
  description = "Namnen på de skapade VMaran"
  value       = proxmox_virtual_environment_vm.learning_vm[*].name
}