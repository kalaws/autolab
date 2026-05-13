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

## Komponenter

### Packer — VM-template

Bygger en Ubuntu 24.04 LTS-template i Proxmox med Q35-maskintyp och UEFI (OVMF). Autoinstall körs via en cloud-init CIDATA-ISO. Template:en rensas (SSH host keys, machine-id) och cloud-init konfigureras för Proxmox-kompatibelt NoCloud-läge. Terraform klonar sedan denna template för varje Kubernetes-nod.

### Terraform — provisionering

Provisionerar hela infrastrukturen mot Proxmox via `bpg/proxmox`-providern. Skapar:

1. **Ansible control node** (LXC) — med nesting aktiverat för att köra Ansible
2. **Vault** (LXC) — enkel container för HashiCorp Vault
3. **Kubernetes control plane** (VM klonad från Packer-template)
4. **Kubernetes workers** (VMs klonade från Packer-template, antal styrs av `workers`-variabeln)

Terraform genererar två ED25519-nyckelpar:
- `terraform_ssh` — för Terraform-provisioners mot LXC-containers
- `ansible_ssh` — injiceras i alla noder; privnyckeln kopieras till Ansible control node

Bootstrap-provisioners körs via `terraform_data`-resurser med `local-exec` och sköter installation av Ansible, Git och kloning av repot till `/opt/autolab` på control node. Ansible-inventory genereras dynamiskt med de DHCP-tilldelade IP-adresserna och skrivs till control node.

### Ansible — konfigurationshantering

Master-playbooken `site.yml` kör följande plays i ordning:

| # | Play | Roller | Syfte |
|---|---|---|---|
| 1 | Ansible control node | `common` | Admin-användare med SSH-nyckel |
| 2 | Bootstrap Vault | `common`, `vault` | Installera, initialisera och unseala Vault |
| 3 | Vault AppRole | `vault-config` | Skapa AppRole och lagra DockerHub-credentials |
| 4 | K8s prerequisites | `common`, `k8s-common` | containerd, kubeadm, kubelet, kubectl |
| 5 | Control plane | `k8s-master` | `kubeadm init`, Calico CNI |
| 6 | Vault → K8s | `k8s-vault` | Hämta secrets från Vault till control plane |
| 7 | Workers | `k8s-worker` | Joina workers med `kubeadm join` |
| 8 | Sårbar webbapp | `k8s-vulnerable` | Driftsätt webbapp med avsiktliga säkerhetsbrister |

### Rollen vault

Installerar HashiCorp Vault från HashiCorps officiella apt-repository, konfigurerar Vault med en Jinja2-template och väntar på att API:et svarar. Initialiserar och unsealar Vault automatiskt via `init.yml`.

### Rollen vault-config

Konfigurerar ett AppRole-autentiseringssätt i Vault och lagrar DockerHub-credentials (från `secrets.yml`) under `secret/dockerhub`. K8s-noden hämtar sedan dessa credentials via `k8s-vault`-rollen för att bygga och pusha Docker-images.

### Rollen k8s-master

Kör `kubeadm init` med pod-nätverket `10.244.0.0/16`, installerar Calico som CNI-plugin och sparar join-kommandot som ett Ansible-fact för workers. Installerar även Docker CE (behövs för `k8s-vulnerable`-rollens image-bygge).

### Rollen k8s-vulnerable

Driftsätter en avsiktligt sårbar webbapplikation för säkerhetsövning. Hämtar DockerHub-credentials från Vault, bygger och pushar en Docker-image, och applicerar Kubernetes-manifest med följande avsiktliga brister:

- ClusterAdmin-service account (överprivilegerad)
- Secrets monterade som env-variabler i klartext i manifestet
- Exponerad via NodePort

### Rollen k8s-security-tools

Kör `kube-bench` som ett Kubernetes Job. kube-bench kontrollerar klustret mot CIS Kubernetes Benchmark och sparar resultatet till `/tmp/kube-bench-results.txt` på control plane.

---

*Skapad av: Simon Hallberg och Simon Rundell*  
*Kurs: Virtualiseringsteknik*  
*Datum: 2026-05-13*
