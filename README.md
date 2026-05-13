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

## Krav och förutsättningar

**Programvara som måste vara installerad på operatörsdatorn:**

- [Terraform](https://developer.hashicorp.com/terraform) ≥ 1.6
- [Packer](https://developer.hashicorp.com/packer) ≥ 1.10
- [Git](https://git-scm.com/)

**Proxmox-krav:**

- Proxmox VE 8.x med API-token för Terraform och Packer
- LXC-template `ubuntu-24.04-standard_24.04-2_amd64.tar.zst` nedladdad till local storage
- Ubuntu 24.04 Server ISO tillgänglig på Proxmox-noden (för Packer)
- Nätverksbridge `vnet1` (eller anpassa `bridge_wan` i `resources.auto.tfvars`)

**Hårdvarukrav på Proxmox-hypervisorn:**

- Minst 16 GB RAM (5 noder, totalt ~13 GB allokerat)
- Minst 130 GB ledigt diskutrymme

**Secrets-fil:**

Skapa `secrets.yml` baserat på `secrets.yml_example` innan `terraform apply`. Se [Secrets](#secrets).

---

## Kom igång

```bash
# 1. Klona repot
git clone https://github.com/kalaws/autolab.git
cd autolab

# 2. Sätt upp Proxmox API-credentials
cp .env_example .env
# Redigera .env med ditt Proxmox-endpoint, token-id och token-secret
source .env

# 3. Skapa secrets-filen
cp secrets.yml_example secrets.yml
# Redigera secrets.yml med DockerHub-credentials

# 4. Ladda ner images till Proxmox (görs en gång via Proxmox-webbgränssnittet eller CLI)
#
#    ISO för Packer (VM-template):
#      ubuntu-24.04.4-live-server-amd64.iso → local:iso/
#      https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso
#
#    LXC-template för Terraform (Ansible control node och Vault):
#      ubuntu-24.04-standard_24.04-2_amd64.tar.zst → local:vztmpl/
#      https://images.linuxcontainers.org/ubuntu/24.04/
#      (eller via Proxmox: Datacenter → pve → local → CT Templates → Download from URL)

# 5. Bygg Kubernetes VM-template med Packer (körs en gång)
cd packer
packer init .
packer build .
cd ..

# 6. Provisionera hela infrastrukturen med Terraform
cd terraform
terraform init
terraform apply
```

`terraform apply` sköter allt: skapar noder, bootstrappar Ansible control node, kör Vault-setup och kör sedan hela Ansible-playbooken. Processen tar ca 15–25 minuter.

**Verifiera att klustret är uppe:**

```bash
# SSH in på control node (IP visas i terraform output)
ssh admin@<control-node-ip>

# Kör verifieringsplaybooken från control node
cd /opt/autolab
sudo -u ansible ansible-playbook ansible/verify.yml -i ansible/inventory.ini
```

**Kör säkerhetsanalysen (kube-bench):**

```bash
sudo -u ansible ansible-playbook ansible/security.yml -i ansible/inventory.ini
# Resultat sparas på control plane: /tmp/kube-bench-results.txt
```

**Driftsätt den sårbara webbappen separat:**

```bash
sudo -u ansible ansible-playbook ansible/site.yml -i ansible/inventory.ini --tags vulnerable
```

---

## Secrets

Filen `secrets.yml` måste skapas lokalt och **ska aldrig committas till Git** (den finns i `.gitignore`).

```bash
cp secrets.yml_example secrets.yml
# Fyll i dockerhub_username och dockerhub_token
```

Terraform kopierar automatiskt `secrets.yml` till Ansible control node under `terraform apply` och raderar den sedan från noden när Vault har konfigurerats. Secrets lagras därefter i HashiCorp Vault och hämtas därifrån av Ansible vid behov.

Proxmox API-credentials hanteras via `.env` och exporteras som miljövariabler — de skickas aldrig in i Terraform-state.

```yaml
# secrets.yml_example
dockerhub_username: ""
dockerhub_token: ""

vault_secrets:
  dockerhub:
    username: "{{ dockerhub_username }}"
    token: "{{ dockerhub_token }}"
```

---

## Säkerhetsåtgärder

Följande säkerhetsåtgärder är implementerade och automatiserade via Terraform och Ansible:

| Åtgärd | Var | Hur verifieras det |
|---|---|---|
| Unika ED25519-nyckelpar per syfte | Alla noder | Terraform genererar `terraform_ssh` och `ansible_ssh` separat |
| Root-inloggning via SSH blockerad (admin-user används) | Alla noder | `sshd -T \| grep permitrootlogin` |
| Secrets raderas från disk efter Vault-import | Ansible control | `ls /opt/autolab/ansible/group_vars/vault/` |
| Proxmox-credentials aldrig i Terraform-state | Operatörsdator | credentials hanteras via miljövariabler |
| AppRole med begränsad policy i Vault | Vault | `vault policy read k8s-policy` |
| Operatörens SSH-nyckel injiceras via Ansible | Alla noder | `authorized_key`-task i `common`-rollen |

---

## Säkerhetsanalys

### Avsiktliga brister i k8s-vulnerable

Rollen `k8s-vulnerable` innehåller medvetet följande säkerhetsbrister som underlag för analys:

**Brist 1: ClusterAdmin service account**

Webbappens pod kör med ett service account som har `cluster-admin`-roll — fulla rättigheter i klustret. En angripare som komprometterar podden kan kontrollera hela klustret via Kubernetes API.

*Åtgärd:* Skapa ett dedikerat service account med minsta nödvändiga RBAC-rättigheter (principen om minsta privilegium).

*Syfte i denna miljö:* Illustrera risken med överprivilegerade service accounts och hur kube-bench flaggar avsaknad av RBAC-härdning.

---

**Brist 2: Secrets som env-variabler i manifest**

Kubernetes-secrets monteras som `env` i pod-specen. Secrets är base64-kodade i etcd men synliga i klartext via `kubectl describe pod` och `kubectl exec`.

*Åtgärd:* Montera secrets som filer med restriktiva filrättigheter, eller integrera en extern secrets manager (Vault Agent Injector / ESO).

*Syfte i denna miljö:* Visa att Kubernetes Secrets inte är krypterade som standard och att env-variabler är ett sämre monteringsalternativ än filer.

---

**Brist 3: NodePort utan autentisering**

Webbapplikationen exponeras via NodePort och är nåbar från alla nätverksgränssnitt utan autentisering.

*Åtgärd:* Använd en Ingress-controller med TLS-terminering och autentisering, eller begränsa NodePort-åtkomst via nätverkspolicyer.

---

### Kvarvarande brister i infrastrukturen

**Brist 4: Okrypterad intern Kubernetes-trafik**

Pod-till-pod-kommunikation inom klustret sker okrypterat (Calico utan WireGuard/eBPF-kryptering). En angripare med åtkomst till nodnivå kan lyssna av trafiken.

*Åtgärd:* Aktivera WireGuard-kryptering i Calico eller installera ett service mesh (Istio/Linkerd) för mTLS.

*Accepterat i denna miljö eftersom:* Labbmiljö utan externa anslutningar. Risken bedöms som låg.

---

**Brist 5: etcd utan kryptering av secrets**

Kubernetes Secrets lagras okrypterade i etcd som standard. Root-åtkomst till control plane ger tillgång till alla secrets.

*Åtgärd:* Aktivera [Encryption at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/) i `kube-apiserver`.

---

**Brist 6: Komprometterad operatörsdator ger fullständig klusteråtkomst**

Terraform sparar de genererade privata SSH-nycklarna (`terraform/.terraform_ed25519` och `terraform/.ansible_ed25519`) lokalt på operatörsdatorn. Användarna `terraform` och `ansible` har `NOPASSWD:ALL`-sudo på samtliga noder. En angripare som får tillgång till operatörsdatorn får därmed omedelbar root-åtkomst till alla noder utan något ytterligare autentiseringssteg.

*Åtgärd:* Lagra privata nycklar i en hårdvarusäkerhetsnyckel (YubiKey/FIDO2) så att de inte kan kopieras. Begränsa `NOPASSWD`-sudo till specifika kommandon (`ansible`, `kubectl`) istället för `ALL`. Rotera nycklarna efter varje Terraform-körning.

*Accepterat i denna miljö eftersom:* Labbmiljö på ett isolerat nätverk med en enda operatör. I en produktionsmiljö eller flerpersonsmiljö vore detta oacceptabelt.

---

### Vad som skyddar miljön

- Separata SSH-nyckelpar med begränsad livslängd
- Secrets hanteras via HashiCorp Vault och raderas från disk efter import
- Proxmox-credentials exponeras aldrig i versionshanteringen
- kube-bench CIS-benchmark körs automatiserat för att identifiera ytterligare brister

---

## Verifiering

Kör verifieringsplaybooken från Ansible control node:

```bash
sudo -u ansible ansible-playbook /opt/autolab/ansible/verify.yml \
  -i /opt/autolab/ansible/inventory.ini
```

Playbooken kontrollerar:

- Att alla noder svarar och har status `Ready`
- Att control plane har rätt roll (`node-role.kubernetes.io/control-plane`)
- Att workers har rätt roll (`node-role.kubernetes.io/worker`)
- Att alla poddar i `kube-system` är i status `Running`

Förväntat output (förkortat):

```
TASK [Kontrollera att alla noder är Ready]
ok: [LABITS-K8S-master] => LABITS-K8S-master är Ready
ok: [LABITS-K8S-master] => LABITS-K8S-worker-1 är Ready
ok: [LABITS-K8S-master] => LABITS-K8S-worker-2 är Ready

TASK [Säkerställ att alla kube-system-poddar kör]
ok: [LABITS-K8S-master] => Alla kube-system-poddar kör
```
---

## Designval och motivering

### Varför Terraform + Ansible istället för enbart Terraform?

Terraform är bra på att provisionera infrastruktur men saknar idempotent konfigurationshantering av OS-nivå. Ansible hanterar paketinstallation, tjänstkonfiguration och klusterinitiering bättre och gör det möjligt att köra om playbooken utan bieffekter. Kombination: Terraform skapar noderna, Ansible konfigurerar dem.

### Varför LXC för Ansible control och Vault?

Ansible control node och Vault behöver inte kernel-isolation — de kör inga containers och inga privilegierade processer som kräver egna namespaces. LXC-containers startar snabbare, förbrukar mindre RAM och är enklare att provisionera via Proxmox API. Kubernetes-noderna kräver VMs eftersom kubeadm och containerd behöver tillgång till kernel-features som är begränsade i LXC.

### Varför dynamiskt genererade SSH-nyckelpar i Terraform?

Statiska nycklar i repot eller hardkodade i konfiguration är en säkerhetsrisk. Terraform genererar unika nyckelpar vid varje `terraform apply`, lagrar privnycklarna lokalt med `0600`-rättigheter och injicerar publika nycklar i noderna via API. Nycklarna är labbspecifika och försvinner när infrastrukturen rivs.

### Varför HashiCorp Vault för DockerHub-credentials?

Alternativet — att lägga credentials direkt i `secrets.yml` och låta Ansible skicka dem direkt till Kubernetes Secrets — hade fungerat men lämnar credentials synliga som env-variabler i Ansible-output och möjligen i logs. Vault ger ett separat lager: credentials lagras och roteras centralt, och AppRole-autentisering begränsar vilka som kan hämta dem.

### Varför en avsiktligt sårbar webbapp?

`k8s-vulnerable`-rollen existerar för att ha konkreta brister att analysera med kube-bench och för att demonstrera skillnaden mellan en säker och osäker Kubernetes-driftsättning. Bristerna är dokumenterade och avsiktliga — de ger underlag för säkerhetsanalysen i rapporten.

### Varför DockerHub som container registry?

Ett lokalt registry (t.ex. Harbor eller ett Proxmox-hostat registry) hade undvikit beroendet av ett externt konto och internet-åtkomst vid image-push. DockerHub valdes ändå av tre skäl: det kräver noll infrastruktur utöver ett gratis konto, det är den naturliga integrationen för `community.docker`-modulen i Ansible, och det möjliggör att demonstrera hur Vault hanterar externa tjänsters credentials — vilket är ett mer realistiskt scenario än ett internt registry utan autentisering.

Nackdelen är att image-bygget kräver internet-åtkomst från control plane och att DockerHub-credentials måste hanteras som en secret. Det senare är dock i sig ett pedagogiskt poäng: det visar varför Vault behövs.

### Varför Calico som CNI?

Calico stöder NetworkPolicy (till skillnad från Flannel) vilket är ett krav för att kunna demonstrera och testa nätverkssegmentering i klustret. Det är dessutom vältestat med kubeadm och kräver minimal konfiguration för ett labb av denna storlek.

---

*Skapad av: Simon Hallberg och Simon Rundell*  
*Kurs: Virtualiseringsteknik*  
*Datum: 2026-05-13*
