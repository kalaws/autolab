#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: se
    variant: ""
  refresh-installer:
    update: false
  ssh:
    install-server: true
    allow-pw: false
    ssh_quiet_keygen: true
    allow_public_ssh_keys: true
  packages:
    - qemu-guest-agent
    - openssh-server
    - sudo
    - curl
    - cloud-init
  storage:
    layout:
      name: lvm
      sizing-policy: all
    swap:
      size: 0
  user-data:
    package_upgrade: true
    timezone: Europe/Stockholm
    users:
      - name: ubuntu
        groups: [adm, sudo]
        lock-passwd: true
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
        ssh_authorized_keys:
          - SSH_PUBLIC_KEY_PLACEHOLDER
  late-commands:
    - curtin in-target -- systemctl enable qemu-guest-agent
    - curtin in-target -- systemctl enable cloud-init
    - curtin in-target -- apt-get -y autoremove --purge
    - curtin in-target -- apt-get -y clean
    - curtin in-target -- apt-get -y autoclean
    - curtin in-target -- bash -c "rm -rf /tmp/* /var/tmp/*"
    - curtin in-target -- bash -c "find /var/log -type f -exec truncate -s 0 {} \\;"
    - curtin in-target -- bash -c "rm -f /home/ubuntu/.bash_history"
