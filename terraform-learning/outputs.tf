output "vm_id" {
    description = "ID för den skapade VMen"
    value = proxmox_virtual_environment_vm.learning_vm.vm_id
}

output "vm_name" {
    description = "Namnet på den skapde VMen"
    value = proxmox_virtual_environment_vm.learning_vm.vm_name
}