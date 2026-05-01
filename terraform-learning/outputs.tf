output "vm_id" {
  description = "ID för den skapade VMen"
  value       = module.learning_vm.vm_id
}

output "vm_name" {
  description = "Namnet på den skapade VMen"
  value       = module.learning_vm.vm_name
}

output "vm_ip" {
  description = "IP-adressen för VMen"
  value = module.learning_vm.vm_ip  
}