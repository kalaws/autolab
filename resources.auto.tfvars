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
    memory   = 512
    disk     = 8
  }
  k8s_control = {
    hostname = "LABITS-K8S-master"
    cores    = 2
    memory   = 4096
    disk     = 20
  }
  k8s_worker = {
    hostname = "LABITS-K8S-worker"
    cores    = 2
    memory   = 4096
    disk     = 40
  }
}
