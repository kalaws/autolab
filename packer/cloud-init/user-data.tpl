#cloud-config
autoinstall:
  version: 1

  locale: en_US.UTF-8
  keyboard:
    layout: se

  network:
    version: 2
    ethernets:
      eth0:
        dhcp4: true

  apt:
    geoip: false
    preserve_sources_list: false

  identity:
    hostname: ubuntu-jammy-packer
    username: ubuntu
    password: "!"

  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - ${ssh_public_key}

  packages:
    - qemu-guest-agent

  late-commands:
    - systemctl enable qemu-guest-agent
    - cloud-init clean --logs
    # Rensa EFI boot-entries så klonade VM:ar gör fresh UEFI-discovery vid boot
    - efibootmgr | grep -oP 'Boot\K[0-9A-F]{4}(?=\*)' | xargs -I{} efibootmgr -b {} -B || true

  power_state:
    mode: poweroff
