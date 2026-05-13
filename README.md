# AutoLab — Automatiserat Kubernetes-labb på Proxmox

> En fullautomatiserad labbmiljö som provisionerar ett Kubernetes-kluster med HashiCorp Vault på Proxmox via Packer, Terraform och Ansible. Miljön inkluderar en avsiktligt sårbar webbapplikation och ett automatiserat CIS-benchmark-verktyg (kube-bench) för säkerhetsanalys.

---

## Innehållsförteckning

- [Arkitektur](#arkitektur)
- [Miljöer och noder](#miljöer-och-noder)
- [Mappstruktur](#mappstruktur)
- [Komponenter](#komponenter)
- [Krav och förutsättningar](#krav-och-förutsättningar)
- [Kom igång](#kom-igång)
- [Secrets](#secrets)
- [Säkerhetsåtgärder](#säkerhetsåtgärder)
- [Säkerhetsanalys](#säkerhetsanalys)
- [Verifiering](#verifiering)
- [Designval och motivering](#designval-och-motivering)

---

## Arkitektur

![Arkitekturdiagram](docs/architecture.svg)

---

## Miljöer och noder

Alla noder provisioneras av Terraform mot en Proxmox-hypervisor. LXC-containers används för lätta stödtjänster; fullständiga VMs används för Kubernetes-noder (krav för kubeadm).

| Nod | Typ | Roll | CPU | RAM | Disk |
|---|---|---|---|---|---|
| `LABITS-ansible` | LXC | Ansible control node | 1 | 512 MB | 8 GB |
| `LABITS-vault` | LXC | HashiCorp Vault | 1 | 256 MB | 8 GB |
| `LABITS-K8S-master` | VM | Kubernetes control plane | 2 | 4 GB | 20 GB |
| `LABITS-K8S-worker-1` | VM | Kubernetes worker | 2 | 4 GB | 40 GB |
| `LABITS-K8S-worker-2` | VM | Kubernetes worker | 2 | 4 GB | 40 GB |

IP-adresser tilldelas dynamiskt via DHCP och Terraform skriver in dem i Ansible-inventory på control node.

---

## Mappstruktur

```
autolab/
├── packer/
│   ├── ubuntu-2404-q35.pkr.hcl   # Bygger Ubuntu 24.04 Q35/UEFI-template i Proxmox
│   ├── variables.pkr.hcl          # Packer-variabler
│   └── files/
│       ├── 99-pve.cfg             # Cloud-init datasource-config för Proxmox
│       ├── meta-data              # Tom meta-data för autoinstall
│       └── user-data.tpl          # Ubuntu autoinstall-konfiguration (template)
│
├── terraform/
│   ├── main.tf                    # Alla resurser: LXC-containers, VMs, bootstrap-provisioners
│   ├── outputs.tf                 # Outputs (IP-adresser m.m.)
│   ├── variables.tf               # Variabeldefinitioner
│   ├── resources.auto.tfvars      # Resurskonfiguration (hostname, CPU, RAM, disk)
│   └── modules/
│       ├── container/             # Återanvändbar modul för LXC-containers
│       └── virtual-machine/       # Återanvändbar modul för Proxmox VM (klon av Packer-template)
│
├── ansible/
│   ├── site.yml                   # Master playbook — kör alla roller i rätt ordning
│   ├── security.yml               # Playbook för CIS-benchmark (kube-bench)
│   ├── verify.yml                 # Playbook för klusterkontroll
│   ├── requirements.yml           # Ansible Galaxy-collections
│   └── roles/
│       ├── common/                # Skapar admin-användare med SSH-nyckel på alla noder
│       ├── vault/                 # Installerar, initialiserar och unsealar HashiCorp Vault
│       ├── vault-config/          # Konfigurerar AppRole och lagrar secrets i Vault
│       ├── k8s-common/            # Kubernetes-prerequisites: containerd, kubeadm, kubelet, kubectl
│       ├── k8s-master/            # kubeadm init, Calico CNI, Docker CE
│       ├── k8s-vault/             # Hämtar secrets från Vault till control plane
│       ├── k8s-worker/            # Joinar worker-noder till klustret
│       ├── k8s-vulnerable/        # Driftsätter avsiktligt sårbar webbapp (säkerhetsövning)
│       └── k8s-security-tools/    # Kör kube-bench CIS-benchmark som Kubernetes Job
│
├── docs/
│   └── architecture.drawio        # Arkitekturdiagram
│
├── .env_example                   # Mall för Proxmox API-credentials (källa via source)
├── secrets.yml_example            # Mall för secrets.yml
├── .gitignore
└── README.md
```


---

*Skapad av: Simon Hallberg och Simon Rundell*
*Kurs: Virtualiseringsteknik*
*Datum: 2026-05-13*
