#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: se
    variant: ""
  identity:
    hostname: ubuntu-template
    username: ubuntu
    # Lösenord: "ubuntu" (bcrypt-hash). Byts vid kloning via cloud-init.
    password: "$6$rounds=4096$randomsalt$YQxBO5cOdz1FGKPN3ZvOqIu4hP9Y5L7Ux7b6F3kKjWRdGlNe8CfNJqHY6m1Ld3nQIpB7AqH9gVxT0qOBjIq."
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - ${ssh_public_key}
  network:
    network:
      version: 2
      ethernets:
        any:
          match:
            name: "en*"
          dhcp4: true
          dhcp6: false
  storage:
    layout:
      name: lvm
      sizing-policy: all
    swap:
      size: 0
  packages:
    - qemu-guest-agent
    - openssh-server
    - sudo
    - curl
    - cloud-init
  user-data:
    users:
      - name: ubuntu
        groups: [adm, sudo]
        lock-passwd: false
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys:
          - ${ssh_public_key}
  late-commands:
    # Aktivera qemu-guest-agent
    - curtin in-target -- systemctl enable qemu-guest-agent
    # Se till att cloud-init körs vid kloning
    - curtin in-target -- systemctl enable cloud-init
