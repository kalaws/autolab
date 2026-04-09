provider "proxmox" {

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
