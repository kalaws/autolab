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
  ct_template = var.ct_template
  memory      = var.resources["ansible"].memory
  cpu_cores   = var.resources["ansible"].cores
  disk        = var.resources["ansible"].disk
  bridge_wan  = var.bridge_wan
  dns_servers = var.dns_servers
  ssh_keys    = [trimspace(tls_private_key.terraform_ssh.public_key_openssh), trimspace(file(pathexpand(var.ssh_public_key_path)))]
  nesting     = true
}

# ============================================
# 2. HashiCorp Vault CT
# ============================================
module "vault" {
  source = "./modules/container"

  ct_name     = var.resources["vault"].hostname
  ct_template = var.ct_template
  memory      = var.resources["vault"].memory
  cpu_cores   = var.resources["vault"].cores
  disk        = var.resources["vault"].disk
  bridge_wan  = var.bridge_wan
  dns_servers = var.dns_servers
  ssh_keys    = [trimspace(tls_private_key.terraform_ssh.public_key_openssh), trimspace(file(pathexpand(var.ssh_public_key_path)))]
}

locals {
  control_ip = try(module.ansible.ipv4_address, "")
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
    command = <<-EOT
      # Proxmox populerar ipv4-kartan asynkront — falla tillbaka på API-polling vid race condition
      resolve_proxmox_ip() {
        local vmid=$1 endpoint=$PROXMOX_VE_ENDPOINT
        if [ -n "$PROXMOX_VE_API_TOKEN" ]; then
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

      VMID="${module.ansible.vm_id}"
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
# 4. Bootstrappa HashiCorp Vault
# ============================================
resource "terraform_data" "bootstrap_vault" {
  depends_on = [
    module.vault,
    terraform_data.bootstrap_control,
  ]

  provisioner "local-exec" {
    command = <<-EOT
      VAULT_IP="${module.vault.ipv4_address}"
      SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.terraform_ssh_private.filename}"

      echo "Väntar på SSH till vault ($VAULT_IP)..."
      until ssh $SSH_OPTS root@$VAULT_IP true 2>/dev/null; do sleep 5; done

      echo "Installerar HashiCorp Vault..."
      ssh $SSH_OPTS root@$VAULT_IP "
        set -e
        apt-get update -qq
        apt-get install -y gpg curl
        curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo \"deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\" | tee /etc/apt/sources.list.d/hashicorp.list
        apt-get update -qq
        apt-get install -y vault
        mkdir -p /opt/vault/data
        chown vault:vault /opt/vault/data
      "

      echo "Konfigurerar Vault..."
      printf '%s\n' \
        'ui = true' \
        '' \
        'storage "raft" {' \
        '  path    = "/opt/vault/data"' \
        '  node_id = "vault-1"' \
        '}' \
        '' \
        'listener "tcp" {' \
        '  address     = "0.0.0.0:8200"' \
        '  tls_disable = true' \
        '}' \
        '' \
        'api_addr     = "http://${module.vault.ipv4_address}:8200"' \
        'cluster_addr = "http://${module.vault.ipv4_address}:8201"' \
        | ssh $SSH_OPTS root@$VAULT_IP 'tee /etc/vault.d/vault.hcl > /dev/null'

      ssh $SSH_OPTS root@$VAULT_IP "systemctl enable vault && systemctl restart vault"

      echo "Väntar på Vault API..."
      until ssh $SSH_OPTS root@$VAULT_IP \
        'VAULT_ADDR=http://127.0.0.1:8200 vault status 2>&1 | grep -q "Seal Type"' 2>/dev/null; do
        sleep 3
      done

      echo "Initierar Vault..."
      INIT_OUTPUT=$(ssh $SSH_OPTS root@$VAULT_IP \
        'VAULT_ADDR=http://127.0.0.1:8200 vault operator init -key-shares=1 -key-threshold=1 -format=json')
      echo "$INIT_OUTPUT" > ${path.module}/.vault-init.json
      chmod 600 ${path.module}/.vault-init.json

      UNSEAL_KEY=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['unseal_keys_b64'][0])")
      ROOT_TOKEN=$(echo "$INIT_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")

      echo "Förseglar Vault..."
      ssh $SSH_OPTS root@$VAULT_IP "VAULT_ADDR=http://127.0.0.1:8200 vault operator unseal $UNSEAL_KEY"

      echo "Aktiverar KV secrets engine och skapar ansible-policy..."
      ssh $SSH_OPTS root@$VAULT_IP "
        set -e
        export VAULT_ADDR=http://127.0.0.1:8200
        export VAULT_TOKEN=$ROOT_TOKEN
        vault secrets enable -path=secret kv-v2
        printf '%s\n' \
          'path \"secret/data/*\" {' \
          '  capabilities = [\"read\", \"list\"]' \
          '}' > /tmp/ansible-policy.hcl
        vault policy write ansible-read /tmp/ansible-policy.hcl
        rm /tmp/ansible-policy.hcl
      "

      echo "Skapar Ansible-token..."
      ANSIBLE_TOKEN=$(ssh $SSH_OPTS root@$VAULT_IP \
        "export VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=$ROOT_TOKEN && vault token create -policy=ansible-read -format=json" | \
        python3 -c "import sys,json; print(json.load(sys.stdin)['auth']['client_token'])")

      echo "Skriver Vault-konfiguration till ansible-noden..."
      CONTROL_IP="${local.control_ip}"
      CONTROL_SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -i ${local_sensitive_file.terraform_ssh_private.filename}"
      ssh $CONTROL_SSH_OPTS ${var.terraform_ssh_user}@$CONTROL_IP "
        printf '%s\n' '$ANSIBLE_TOKEN' | sudo tee /home/ansible/.vault-token > /dev/null
        sudo chmod 600 /home/ansible/.vault-token
        sudo chown ansible:ansible /home/ansible/.vault-token
        sudo bash -c 'printf \"export VAULT_ADDR=http://${module.vault.ipv4_address}:8200\nexport VAULT_TOKEN_FILE=/home/ansible/.vault-token\n\" >> /home/ansible/.bashrc'
      "

      echo "Vault bootstrappad — init-data sparad i .vault-init.json (KÄNSLIG FIL)"
    EOT
  }
}

# ============================================
# 5. Klona Kubernetes control node VM
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
# 6. Klona Kubernetes worker nodes VM
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
# 7. Skapa admin-användare på k8s-noder och kör reboot efter cloud-init
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
      
        echo "Startar om $ip för att fullfölja cloud-init..."
        ssh $SSH_OPTS ${var.ansible_user}@$ip "sudo reboot" || true
        sleep 15
        until ssh $SSH_OPTS ${var.ansible_user}@$ip true 2>/dev/null; do sleep 5; done
        echo "$ip är tillbaka"
      }


      create_admin "${module.k8s_control.ipv4_address}"
      %{~ for name, vm in module.k8s_worker }
      create_admin "${vm.ipv4_address}"
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
    command = <<-EOT
      resolve_proxmox_ip() {
        local vmid=$1 endpoint="$PROXMOX_VE_ENDPOINT"
        if [ -n "$PROXMOX_VE_API_TOKEN" ]; then
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

      VMID="${module.ansible.vm_id}"
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
