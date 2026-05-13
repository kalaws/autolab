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

Arkitekturdiagrammet finns i [`docs/architecture.drawio`](docs/architecture.drawio) och kan öppnas direkt på GitHub eller i draw.io / diagrams.net.



---

*Skapad av: Simon Hallberg och Simon Rundell*
*Kurs: Virtualiseringsteknik*
*Datum: 2026-05-13*
