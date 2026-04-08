provider "proxmox" {
  pm_api_url      = "https://100.90.144.70:8006/api2/json"
  pm_user         = "root@pam"
  pm_password     = "rootpam"
  pm_tls_insecure = true
}

resource "proxmox_vm_qemu" "test_vm" {
  name        = "terraform-test"
  target_node = "proxmox"

  clone = "ubuntu-22.04-template"

  cores  = 1
  memory = 1024

  network {
    model  = "virtio"
    bridge = "vmbr0"
  }
}