github_branch = "10-project-init"
github_owner  = "kalaws"

node_name       = "pve"
packer_template = ["ubuntu-2404-q35-template"]
ct_template     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"

# Definiera resurser för varje VM/CT
resources = {
  ansible = {
    hostname = "LABITS-ansible"
    cores    = 1
    memory   = 512
    disk     = 8
  }
  vault = {
    hostname = "LABITS-vault"
    cores    = 1
    memory   = 256
    disk     = 8
  }
  k8s_control = {
    hostname = "LABITS-K8S-master"
    cores    = 2
    memory   = 4096
    disk     = 40
  }
  k8s_worker = {
    hostname = "LABITS-K8S-worker"
    cores    = 2
    memory   = 4096
    disk     = 40
  }
}

# Antal k8s workers
workers = ["1", "2"]
