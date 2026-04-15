output "ansible_control_ip" {
  value = try(proxmox_virtual_environment_container.ansible.ipv4["eth0"], "not available yet")
}

output "ansible_target_ips" {
  value = {
    for name, ct in proxmox_virtual_environment_container.k8s_control :
    name => try(ct.ipv4["eth0"], "not available yet")
  }
}