output "ubuntu_packer_id" {
  value       = proxmox_virtual_environment_vm.ubuntu_jammy_packer_template.id
  description = "VM-ID för base-templaten – används av Packer"
}
