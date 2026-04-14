output "ansible_control_ip" {
  value = try(proxmox_virtual_environment_container.ansible_control.ipv4["eth0"], "not available yet")
}