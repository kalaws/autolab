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
    # Ta bort SSH host keys så klonade VM:ar genererar egna
    - rm -f /target/etc/ssh/ssh_host_*
    # Nollställ machine-id så klonade VM:ar får unika identiteter
    - truncate -s 0 /target/etc/machine-id
    - rm -f /target/var/lib/dbus/machine-id
    # Rensa apt-cache
    - apt-get clean
    # Rensa EFI boot-entries så klonade VM:ar gör fresh UEFI-discovery vid boot
    - efibootmgr | grep -oP 'Boot\K[0-9A-F]{4}(?=\*)' | xargs -I{} efibootmgr -b {} -B || true
    # Återställ cloud-init så det körs om vid första boot av klonad VM
    - cloud-init clean --logs

  power_state:
    mode: poweroff
