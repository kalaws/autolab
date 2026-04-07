#cloud-config
autoinstall:
  version: 1

  locale: en_US.UTF-8
  keyboard:
    layout: se

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

  power_state:
    mode: poweroff
