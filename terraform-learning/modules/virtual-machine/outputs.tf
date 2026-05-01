output "vm_id" {
    description = "ID för den skapade VMen"
    value = proxmox_virtual_environment_vm.vm.vm_id
}

output "vm_name" {
    description = "Namnet på den skapade VMen"
    value = proxmox_virtual_environment_vm.vm.vm.name
}