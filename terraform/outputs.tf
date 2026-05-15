output "ansible" {
  value = {
    hostname = "${var.resources["ansible"].hostname}.${var.domain}"
    ip       = try(module.ansible.ipv4_address, "not available yet")
  }
}

output "vault" {
  value = {
    hostname = "${var.resources["vault"].hostname}.${var.domain}"
    ip       = try(module.vault.ipv4_address, "not available yet")
  }
}

output "k8s_control" {
  value = {
    hostname = "${var.resources["k8s_control"].hostname}.${var.domain}"
    ip       = try(module.k8s_control.ipv4_address, "not available yet")
  }
}

output "k8s_workers" {
  value = {
    for w in var.workers :
    "${var.resources["k8s_worker"].hostname}-${w}.${var.domain}" => try(module.k8s_worker[w].ipv4_address, "not available yet")
  }
}
