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
# 1. Ansible control node CT
# ============================================
module "ansible" {
  source = "./modules/container"

  ct_name     = var.resources["ansible"].hostname
  node_name   = var.node_name
  ct_template = var.ct_template
  memory      = var.resources["ansible"].memory
  cpu_cores   = var.resources["ansible"].cores
  disk        = var.resources["ansible"].disk
  bridge_wan  = var.bridge_wan
  ssh_keys    = [trimspace(tls_private_key.terraform_ssh.public_key_openssh), trimspace(file(pathexpand(var.ssh_public_key_path)))]
  nesting     = true
}

# ============================================
# 2. HashiCorp Vault CT
# ============================================
module "vault" {
  source = "./modules/container"

  ct_name     = var.resources["vault"].hostname
  node_name   = var.node_name
  ct_template = var.ct_template
  memory      = var.resources["vault"].memory
  cpu_cores   = var.resources["vault"].cores
  disk        = var.resources["vault"].disk
  bridge_wan  = var.bridge_wan
  ssh_keys    = [trimspace(tls_private_key.terraform_ssh.public_key_openssh), trimspace(file(pathexpand(var.ssh_public_key_path)))]
  nesting     = true
}

locals {
  target_ips = merge(
    { "control" = module.k8s_control.ipv4_address },
    { for name, vm in module.k8s_worker : name => vm.ipv4_address }
  )
}

# ============================================
# 3. Bootstrappa Ansible control node
# ============================================
resource "terraform_data" "bootstrap_control" {
  depends_on = [
    module.ansible,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      # resolve_proxmox_ip <vmid> — frågar Proxmox API om aktuell IP för en CT (kräver PROXMOX_VE_API_TOKEN)
      source "${path.module}/scripts/proxmox_helpers.sh"

      VMID="${module.ansible.vm_id}"
      echo "Hämtar ansible control IP från Proxmox API (VMID=$VMID)..."
      CONTROL_IP=""
      until [ -n "$CONTROL_IP" ]; do
        CONTROL_IP=$(resolve_proxmox_ip "$VMID")
        [ -z "$CONTROL_IP" ] && sleep 5
      done
      echo "$CONTROL_IP" > "${path.module}/.control_ip"  # Spara ansible control IP för återanvändning i andra bootstrap-script.
      echo "Ansible control IP: $CONTROL_IP"

      ROOT_SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.terraform_ssh_private.filename}"
      SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.terraform_ssh_private.filename}"

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
        "echo 'nameserver $CONTROL_GW' | sudo tee /etc/resolv.conf > /dev/null"

      echo "Kopierar nycklar till control node..."
      scp $SSH_OPTS ${local_sensitive_file.ansible_ssh_private.filename} ${var.terraform_ssh_user}@$CONTROL_IP:/tmp/ansible_ed25519

      echo "Installerar nycklar och SSH-config för ansible-användaren..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP "
        sudo mkdir -p /home/ansible/.ssh
        sudo mv /tmp/ansible_ed25519 /home/ansible/.ssh/ansible_ed25519
        sudo chmod 600 /home/ansible/.ssh/ansible_ed25519
        sudo bash -c 'printf \"Host *.${var.domain}\n  User ansible\n  IdentityFile ~/.ssh/ansible_ed25519\n  StrictHostKeyChecking no\n\" > /home/ansible/.ssh/config'
        sudo chmod 600 /home/ansible/.ssh/config
        sudo chown -R ansible:ansible /home/ansible/.ssh
      "

      echo "Installerar system-wide SSH-config för lab..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP "
        sudo mkdir -p /etc/ssh/ssh_config.d
        printf '%s\n' 'Host *.${var.domain}' '  StrictHostKeyChecking no' '  UserKnownHostsFile /dev/null' | \
          sudo tee /etc/ssh/ssh_config.d/lab.conf > /dev/null
      "

      echo "Installerar Ansible på ansible control node..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP \
        'sudo apt-get update -qq && \
         sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible git && \
         ansible --version'

      echo "Klonar repot till /opt/${var.github_repo}..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP "
        set -e
        sudo mkdir /opt/${var.github_repo}
        sudo chown ansible:ansible /opt/${var.github_repo}
        sudo -u ansible git clone -b ${var.github_branch} https://github.com/${var.github_owner}/${var.github_repo}.git /opt/${var.github_repo}
        sudo find /opt/${var.github_repo} -type d -exec chmod g+rwxs {} +
        sudo find /opt/${var.github_repo} -type f -exec chmod g+rw {} +
        sudo usermod -aG ansible admin
        sudo git config --system --add safe.directory /opt/${var.github_repo}
        sudo -u ansible git -C /opt/${var.github_repo} config core.sharedRepository group
      "

      echo "Skriver operatörens publika nyckel till group_vars..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP "
        sudo mkdir -p /opt/${var.github_repo}/ansible/group_vars/all
        printf 'admin_ssh_pubkey: \"%s\"\n' '${trimspace(file(pathexpand(var.ssh_public_key_path)))}' | \
          sudo tee /opt/${var.github_repo}/ansible/group_vars/all/operator.yml > /dev/null
        sudo chown ansible:ansible /opt/${var.github_repo}/ansible/group_vars/all/operator.yml
        sudo chmod 644 /opt/${var.github_repo}/ansible/group_vars/all/operator.yml
      "
    EOT
  }
}

# ============================================
# 4. Bootstrappa HashiCorp Vault
# ============================================
resource "terraform_data" "bootstrap_vault" {
  depends_on = [
    module.vault,
    terraform_data.bootstrap_control,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      # resolve_proxmox_ip <vmid> — frågar Proxmox API om aktuell IP för en CT (kräver PROXMOX_VE_API_TOKEN)
      source "${path.module}/scripts/proxmox_helpers.sh"

      VMID="${module.vault.vm_id}"
      echo "Hämtar vault IP från Proxmox API (VMID=$VMID)..."
      VAULT_IP=""
      until [ -n "$VAULT_IP" ]; do
        VAULT_IP=$(resolve_proxmox_ip "$VMID")
        [ -z "$VAULT_IP" ] && sleep 5
      done
      echo "Vault IP: $VAULT_IP"

      SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.terraform_ssh_private.filename}"

      echo "Väntar på SSH till vault ($VAULT_IP)..."
      until ssh $SSH_OPTS root@$VAULT_IP true 2>/dev/null; do sleep 5; done

      echo "Konfigurerar DNS på vault..."
      VAULT_GW=$(ssh $SSH_OPTS root@$VAULT_IP "ip route show default | awk '{print \$3; exit}'")
      ssh $SSH_OPTS root@$VAULT_IP "echo 'nameserver $VAULT_GW' > /etc/resolv.conf"

      CONTROL_IP=$(cat "${path.module}/.control_ip")
      echo "Ansible control IP: $CONTROL_IP"

      echo "Skapar bootstrap-användare på vault..."
      ssh $SSH_OPTS root@$VAULT_IP "
        set -e
        for user in terraform ansible; do
          useradd -m -s /bin/bash \$user 2>/dev/null || true
          printf '%s ALL=(ALL) NOPASSWD:ALL\n' \$user | tee /etc/sudoers.d/\$user > /dev/null
          chmod 440 /etc/sudoers.d/\$user
          mkdir -p /home/\$user/.ssh
          chmod 700 /home/\$user/.ssh
        done
        printf '%s\n' '${trimspace(tls_private_key.terraform_ssh.public_key_openssh)}' \
          | tee /home/terraform/.ssh/authorized_keys > /dev/null
        printf '%s\n' '${trimspace(tls_private_key.ansible_ssh.public_key_openssh)}' \
          | tee /home/ansible/.ssh/authorized_keys > /dev/null
        for user in terraform ansible; do
          chmod 600 /home/\$user/.ssh/authorized_keys
          chown -R \$user:\$user /home/\$user/.ssh
        done
      "

      echo "Kopierar secrets.yml till ansible-noden..."
      scp $SSH_OPTS "${path.module}/../secrets.yml" ${var.terraform_ssh_user}@$CONTROL_IP:/tmp/vault_secrets.yml
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP "
        sudo mkdir -p /opt/${var.github_repo}/ansible/group_vars/vault
        sudo mv /tmp/vault_secrets.yml /opt/${var.github_repo}/ansible/group_vars/vault/secrets.yml
        sudo chown ansible:ansible /opt/${var.github_repo}/ansible/group_vars/vault/secrets.yml
        sudo chmod 600 /opt/${var.github_repo}/ansible/group_vars/vault/secrets.yml
      "

      echo "Installerar Ansible-collections..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP \
        "sudo -u ansible ansible-galaxy collection install \
          -r /opt/${var.github_repo}/ansible/requirements.yml"

      echo "Bootstrappar Vault via Ansible..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP "
        sudo -u ansible bash -c 'printf \"[vault]\n$VAULT_IP\n\" \
          > /tmp/vault_inventory.ini'
        sudo -u ansible ansible-playbook \
          -i /tmp/vault_inventory.ini \
          --limit vault \
          /opt/${var.github_repo}/ansible/site.yml
        sudo rm -f /tmp/vault_inventory.ini
      "

      echo "Rensar secrets.yml från ansible-noden..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP \
        "sudo rm -f /opt/${var.github_repo}/ansible/group_vars/all/secrets.yml"

      echo "Raderar secrets.yml från ansible-noden..."
      ssh $SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP \
        "sudo rm -f /opt/${var.github_repo}/ansible/group_vars/vault/secrets.yml"

      echo "Vault bootstrappad."
    EOT
  }
}

# ============================================
# 5. Klona Kubernetes control node VM
# ============================================
module "k8s_control" {
  source = "./modules/virtual-machine"

  vm_name                = var.resources["k8s_control"].hostname
  node_name              = var.node_name
  packer_template        = var.packer_template
  memory                 = var.resources["k8s_control"].memory
  cpu_cores              = var.resources["k8s_control"].cores
  disk                   = var.resources["k8s_control"].disk
  bridge_wan             = var.bridge_wan
  ansible_user           = var.ansible_user
  ansible_ssh_public_key = trimspace(tls_private_key.ansible_ssh.public_key_openssh)
}

# ============================================
# 6. Klona Kubernetes worker nodes VM
# ============================================
module "k8s_worker" {
  source   = "./modules/virtual-machine"
  for_each = toset(var.workers)

  vm_name                = "${var.resources["k8s_worker"].hostname}-${each.key}"
  node_name              = var.node_name
  packer_template        = var.packer_template
  memory                 = var.resources["k8s_worker"].memory
  cpu_cores              = var.resources["k8s_worker"].cores
  disk                   = var.resources["k8s_worker"].disk
  bridge_wan             = var.bridge_wan
  ansible_user           = var.ansible_user
  ansible_ssh_public_key = trimspace(tls_private_key.ansible_ssh.public_key_openssh)
}

# ============================================
# 7. Skapa admin-användare på k8s-noder och kör reboot efter cloud-init
# ============================================
resource "terraform_data" "create_admin_k8s" {
  depends_on = [
    module.k8s_control,
    module.k8s_worker,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.ansible_ssh_private.filename}"

      reboot_node() {
        local ip=$1
        echo "Väntar på SSH till $ip..."
        until ssh $SSH_OPTS ${var.ansible_user}@$ip true 2>/dev/null; do sleep 5; done

        echo "Startar om $ip för att fullfölja cloud-init..."
        ssh $SSH_OPTS ${var.ansible_user}@$ip "sudo reboot" || true
        sleep 15
        until ssh $SSH_OPTS ${var.ansible_user}@$ip true 2>/dev/null; do sleep 5; done
        echo "$ip är tillbaka"
      }


      reboot_node "${module.k8s_control.ipv4_address}"
      %{~ for name, vm in module.k8s_worker }
      reboot_node "${vm.ipv4_address}"
      %{~ endfor }
    EOT
  }
}

# ============================================
# 8. Skriv Ansible inventory
# ============================================
resource "terraform_data" "write_inventory" {
  depends_on = [
    module.k8s_control,
    module.k8s_worker,
    terraform_data.bootstrap_control,
    terraform_data.bootstrap_vault,
    terraform_data.create_admin_k8s,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      CONTROL_IP=$(cat "${path.module}/.control_ip")
      echo "Ansible control IP: $CONTROL_IP"

      CONTROL_SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.terraform_ssh_private.filename}"

      echo "Skriver inventory på ansible control node..."
      ssh $CONTROL_SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP \
        "sudo -u ansible bash -c 'printf \"[vault]\n${var.resources["vault"].hostname}.${var.domain}\n\n[control_plane]\n${var.resources["k8s_control"].hostname}.${var.domain}\n\n[workers]\n${join("\\n", [for w in var.workers : "${var.resources["k8s_worker"].hostname}-${w}.${var.domain}"])}\n\" > /opt/${var.github_repo}/ansible/inventory.ini'"

      echo "Kör Ansible site.yml..."
      ssh $CONTROL_SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP \
        "sudo -u ansible ansible-playbook \
          /opt/${var.github_repo}/ansible/site.yml \
          -i /opt/${var.github_repo}/ansible/inventory.ini"

    EOT
  }
}
