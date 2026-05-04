terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.100.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "proxmox" {}

module "control_plane" {
  source = "../modules/virtual-machine"

  vm_id     = var.control_plane_id
  vm_name   = var.control_plane_name
  cpu_cores = var.cpu_cores
  memory    = var.memory
  clone_id  = var.clone_id
  node_name = var.node_name
}

module "workers" {
  source = "../modules/virtual-machine"
  count  = var.worker_count

  vm_id     = var.worker_id_start + count.index
  vm_name   = "k8s-worker-${count.index + 1}"
  cpu_cores = var.cpu_cores
  memory    = var.memory
  clone_id  = var.clone_id
  node_name = var.node_name
}

resource "null_resource" "ansible" {
  depends_on = [module.control_plane, module.workers]

  provisioner "local-exec" {
    command = <<-EOT
      cat > ${path.module}/ansible/inventory.ini << 'EOF'
[control_plane]
k8s-control-plane ansible_host=${module.control_plane.vm_ip[1][0]}

[workers]
%{for i, ip in module.workers[*].vm_ip~}
k8s-worker-${i + 1} ansible_host=${ip[1][0]}
%{endfor~}

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_ed25519
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
EOF
    EOT
  }

  provisioner "local-exec" {
    command = "sleep 60 && ansible-playbook -i ${path.module}/ansible/inventory.ini ${path.module}/ansible/playbook.yml"
  }
}