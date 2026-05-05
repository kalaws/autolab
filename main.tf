terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.100.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "proxmox" {}

# SSH-nyckel för Terraform → CT-åtkomst (injiceras via user_account.keys)
resource "tls_private_key" "terraform_ssh" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "terraform_ssh_private" {
  content         = tls_private_key.terraform_ssh.private_key_openssh
  filename        = "${path.module}/.terraform_ed25519"
  file_permission = "0600"
}

# SSH-nyckel för ansible control → targets (injiceras i targets via API, privnyckel kopieras till control)
resource "tls_private_key" "ansible_ssh" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "ansible_ssh_private" {
  content         = tls_private_key.ansible_ssh.private_key_openssh
  filename        = "${path.module}/.ansible_ed25519"
  file_permission = "0600"
}

# ============================================
# 1. Klona Ansible control node CT
# ============================================
resource "proxmox_virtual_environment_container" "ansible" {
  description = "Ansible control node (CT)"
  node_name   = "pve"
  unprivileged = true

  features {
    nesting = true
  }

  initialization {
    hostname = var.resources["ansible"].hostname

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [trimspace(tls_private_key.terraform_ssh.public_key_openssh), trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  memory {
    dedicated = var.resources["ansible"].memory
  }

  cpu {
    cores = var.resources["ansible"].cores
  }
  
  disk {
    datastore_id = "local-lvm"     
    size         = var.resources["ansible"].disk  
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge_wan
  }

  operating_system {
    template_file_id = var.ct_template
    type             = "ubuntu"
  }

  started = true
}

locals {
  control_ip = try(proxmox_virtual_environment_container.ansible.ipv4["eth0"], "")
  target_ips = merge(
    { "control" = module.k8s_control.ipv4_address },
    { for name, vm in module.k8s_worker : name => vm.ipv4_address }
  )
}

# ============================================
# 2. Bootstrappa Ansible control node
# ============================================
resource "terraform_data" "bootstrap_control" {
  depends_on = [
    proxmox_virtual_environment_container.ansible,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      # Proxmox populerar ipv4-kartan asynkront — falla tillbaka på API-polling vid race condition
      resolve_proxmox_ip() {
        local vmid=$1 endpoint=$PROXMOX_VE_ENDPOINT"
        if [ -n "${PROXMOX_VE_API_TOKEN:-}" ]; then
          AUTH="-H \"Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN\""
        else
          local ticket
          ticket=$(curl -fsSk -X POST "$endpoint/api2/json/access/ticket" \
            -d "username=$PROXMOX_VE_USERNAME&password=$PROXMOX_VE_PASSWORD" | \
            python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ticket'])" 2>/dev/null)
          AUTH="-b \"PVEAuthCookie=$ticket\""
        fi
        eval curl -fsSk $AUTH "$endpoint/api2/json/nodes/pve/lxc/$vmid/interfaces" 2>/dev/null | \
          python3 -c "
import sys,json
try:
    d=json.load(sys.stdin).get('data',[])
    print(next((i['inet'].split('/')[0] for i in d if i.get('name')=='eth0' and 'inet' in i),''))
except: print('')
" 2>/dev/null
      }

      VMID="${proxmox_virtual_environment_container.ansible.vm_id}"
      CONTROL_IP="${local.control_ip}"
      if [ -z "$CONTROL_IP" ]; then
        echo "IP ej tillgänglig i state — hämtar från Proxmox API (VMID=$VMID)..."
        until [ -n "$CONTROL_IP" ]; do
          CONTROL_IP=$(resolve_proxmox_ip "$VMID")
          [ -z "$CONTROL_IP" ] && sleep 5
        done
      fi
      echo "Ansible control IP: $CONTROL_IP"

      ROOT_SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.terraform_ssh_private.filename}"
      SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.terraform_ssh_private.filename}"

      echo "Väntar på SSH till ansible control ($CONTROL_IP)..."
      until ssh $ROOT_SSH_OPTS root@$CONTROL_IP true 2>/dev/null; do sleep 5; done

      echo "Skapar användare på ansible control node..."
      ssh $ROOT_SSH_OPTS root@$CONTROL_IP "
        setup_user() {
          local user=\$1 key=\$2
          useradd -m -s /bin/bash \$user
          echo \"\$user ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/\$user
          chmod 440 /etc/sudoers.d/\$user
          mkdir -p /home/\$user/.ssh
          echo \"\$key\" > /home/\$user/.ssh/authorized_keys
          chown -R \$user:\$user /home/\$user/.ssh
          chmod 700 /home/\$user/.ssh
          chmod 600 /home/\$user/.ssh/authorized_keys
        }
        setup_user ${var.terraform_ssh_user} '${tls_private_key.terraform_ssh.public_key_openssh}'
        setup_user ${var.ansible_user}       '${tls_private_key.ansible_ssh.public_key_openssh}'
        setup_user admin                      '${file(pathexpand(var.ssh_public_key_path))}'
      "

      echo "Väntar på SSH som terraform-användare..."
      until ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP true 2>/dev/null; do sleep 5; done

      echo "Hämtar gateway från ansible control..."
      CONTROL_GW=$(ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP "ip route show default | awk '{print \$3; exit}'")
      echo "Gateway: $CONTROL_GW"

      echo "Konfigurerar DNS på ansible control ($CONTROL_GW)..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP \
        "{ echo 'nameserver $CONTROL_GW'; %{ for dns in var.dns_servers ~}echo 'nameserver ${dns}'; %{ endfor ~}} > /etc/resolv.conf"
      if ! ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP \
        "python3 -c 'import socket; socket.setdefaulttimeout(2); socket.getaddrinfo(\"packages.ubuntu.com\", 80)' 2>/dev/null"; then
        echo "WARNING: Gateway $CONTROL_GW svarar inte på DNS — faller tillbaka på ${join(", ", var.dns_servers)}"
      fi

      echo "Kopierar nycklar till control node..."
      scp $SSH_OPTS ${local_sensitive_file.ansible_ssh_private.filename} ${var.terraform_ssh_user}@$CONTROL_IP:/tmp/ansible_ed25519

      echo "Installerar nycklar och SSH-config för ansible-användaren..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP "
        sudo mkdir -p /home/ansible/.ssh
        sudo mv /tmp/ansible_ed25519 /home/ansible/.ssh/ansible_ed25519
        sudo chmod 600 /home/ansible/.ssh/ansible_ed25519
        sudo bash -c 'printf \"Host 10.*\n  User ansible\n  IdentityFile ~/.ssh/ansible_ed25519\n  StrictHostKeyChecking no\n\" > /home/ansible/.ssh/config'
        sudo chmod 600 /home/ansible/.ssh/config
        sudo chown -R ansible:ansible /home/ansible/.ssh
      "

      echo "Installerar SSH-config för admin-användaren..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP "
        sudo mkdir -p /home/admin/.ssh
        sudo cp /home/ansible/.ssh/ansible_ed25519 /home/admin/.ssh/ansible_ed25519
        sudo chmod 600 /home/admin/.ssh/ansible_ed25519
        sudo bash -c 'printf \"Host 10.*\n  User admin\n  IdentityFile ~/.ssh/ansible_ed25519\n  StrictHostKeyChecking no\n\" > /home/admin/.ssh/config'
        sudo chmod 600 /home/admin/.ssh/config
        sudo chown -R admin:admin /home/admin/.ssh
      "

      echo "Installerar Ansible på ansible control node..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP \
        'sudo apt-get update -qq && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible git && \
         ansible --version'

      echo "Klonar repot till /opt/${var.github_repo}..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP "
        set -e
        sudo mkdir /opt/${var.github_repo}
        sudo chown ansible:ansible /opt/${var.github_repo}
        sudo -u ansible git clone https://github.com/${var.github_owner}/${var.github_repo}.git /opt/${var.github_repo}
        sudo find /opt/${var.github_repo} -type d -exec chmod g+rwxs {} +
        sudo find /opt/${var.github_repo} -type f -exec chmod g+rw {} +
        sudo usermod -aG ansible admin
        sudo git config --system --add safe.directory /opt/${var.github_repo}
        sudo -u ansible git -C /opt/${var.github_repo} config core.sharedRepository group
      "
    EOT
  }
}

# ============================================
# 3. Klona Kubernetes control node VM
# ============================================
module "k8s_control" {
  source = "./modules/virtual-machine"

  vm_name                = var.resources["k8s_control"].hostname
  node_name              = "pve"
  packer_template        = var.packer_template
  memory                 = var.resources["k8s_control"].memory
  cpu_cores              = var.resources["k8s_control"].cores
  disk                   = var.resources["k8s_control"].disk
  bridge_wan             = var.bridge_wan
  ansible_user           = var.ansible_user
  ansible_ssh_public_key = trimspace(tls_private_key.ansible_ssh.public_key_openssh)
}

# ============================================
# 4. Klona Kubernetes worker nodes VM
# ============================================
module "k8s_worker" {
  source   = "./modules/virtual-machine"
  for_each = toset(var.workers)

  vm_name                = "${var.resources["k8s_worker"].hostname}-${each.key}"
  node_name              = "pve"
  packer_template        = var.packer_template
  memory                 = var.resources["k8s_worker"].memory
  cpu_cores              = var.resources["k8s_worker"].cores
  disk                   = var.resources["k8s_worker"].disk
  bridge_wan             = var.bridge_wan
  ansible_user           = var.ansible_user
  ansible_ssh_public_key = trimspace(tls_private_key.ansible_ssh.public_key_openssh)
}

# ============================================
# 5. Skapa admin-användare på k8s-noder
# ============================================
resource "terraform_data" "create_admin_k8s" {
  depends_on = [
    module.k8s_control,
    module.k8s_worker,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.ansible_ssh_private.filename}"
      OPERATOR_KEY="${trimspace(file(pathexpand(var.ssh_public_key_path)))}"
      ANSIBLE_KEY="${trimspace(tls_private_key.ansible_ssh.public_key_openssh)}"

      create_admin() {
        local ip=$1
        echo "Väntar på SSH till $ip..."
        until ssh $SSH_OPTS ${var.ansible_user}@$ip true 2>/dev/null; do sleep 5; done
        echo "Skapar admin-användare på $ip..."
        ssh $SSH_OPTS ${var.ansible_user}@$ip "
          sudo useradd -m -s /bin/bash admin 2>/dev/null || true
          printf '%s\n' 'admin ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/admin > /dev/null
          sudo chmod 440 /etc/sudoers.d/admin
          sudo mkdir -p /home/admin/.ssh
          printf '%s\n%s\n' '$OPERATOR_KEY' '$ANSIBLE_KEY' | sudo tee /home/admin/.ssh/authorized_keys > /dev/null
          sudo chmod 700 /home/admin/.ssh
          sudo chmod 600 /home/admin/.ssh/authorized_keys
          sudo chown -R admin:admin /home/admin/.ssh
        "
      }

      create_admin "${module.k8s_control.ipv4_address}"
      %{~ for name, vm in module.k8s_worker }
      create_admin "${vm.ipv4_address}"
      %{~ endfor }
    EOT
  }
}

# ============================================
# 6. Skriv Ansible inventory
# ============================================
resource "terraform_data" "write_inventory" {
  depends_on = [
    module.k8s_control,
    module.k8s_worker,
    terraform_data.bootstrap_control,
    terraform_data.create_admin_k8s,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      resolve_proxmox_ip() {
        local vmid=$1 endpoint="${PROXMOX_VE_ENDPOINT%/}"
        if [ -n "${PROXMOX_VE_API_TOKEN:-}" ]; then
          AUTH="-H \"Authorization: PVEAPIToken=$PROXMOX_VE_API_TOKEN\""
        else
          local ticket
          ticket=$(curl -fsSk -X POST "$endpoint/api2/json/access/ticket" \
            -d "username=$PROXMOX_VE_USERNAME&password=$PROXMOX_VE_PASSWORD" | \
            python3 -c "import sys,json; print(json.load(sys.stdin)['data']['ticket'])" 2>/dev/null)
          AUTH="-b \"PVEAuthCookie=$ticket\""
        fi
        eval curl -fsSk $AUTH "$endpoint/api2/json/nodes/pve/lxc/$vmid/interfaces" 2>/dev/null | \
          python3 -c "
import sys,json
try:
    d=json.load(sys.stdin).get('data',[])
    print(next((i['inet'].split('/')[0] for i in d if i.get('name')=='eth0' and 'inet' in i),''))
except: print('')
" 2>/dev/null
      }

      VMID="${proxmox_virtual_environment_container.ansible.vm_id}"
      CONTROL_IP="${local.control_ip}"
      if [ -z "$CONTROL_IP" ]; then
        echo "IP ej tillgänglig i state — hämtar från Proxmox API (VMID=$VMID)..."
        until [ -n "$CONTROL_IP" ]; do
          CONTROL_IP=$(resolve_proxmox_ip "$VMID")
          [ -z "$CONTROL_IP" ] && sleep 5
        done
      fi

      CONTROL_SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.terraform_ssh_private.filename}"

      echo "Skriver inventory på ansible control node..."
      ssh $CONTROL_SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP \
        "sudo -u ansible bash -c 'mkdir -p /opt/${var.github_repo}/ansible && printf \"[control_plane]\n${module.k8s_control.ipv4_address} ansible_user=${var.ansible_user} ansible_ssh_private_key_file=~/.ssh/ansible_ed25519\n\n[workers]\n${join("\\n", [for name, vm in module.k8s_worker : "${vm.ipv4_address} ansible_user=${var.ansible_user} ansible_ssh_private_key_file=~/.ssh/ansible_ed25519"])}\n\" > /opt/${var.github_repo}/ansible/inventory.ini'"

    EOT
  }
}
