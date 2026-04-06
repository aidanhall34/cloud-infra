# Cloud Infrastructure

> **Cost goal: minimise above all else.** Ceiling ~$10/month. Availability and redundancy are not priorities.

## Cloud Providers

### Linode (Akamai) — ap-southeast (Singapore)

- **Primary region:** ap-southeast (Singapore — lowest-latency AU-adjacent region)

#### Compute

| Name | Type | vCPU | RAM | OS | Role |
|------|------|------|-----|----|------|
| gateway | g6-nanode-1 (x86_64) | 1 | 1GB | Custom Alpine (Packer) | WireGuard VPN, Blocky DNS, Nginx, otelcol-contrib |

#### Networking

- **Firewall:** Linode Cloud Firewall — DROP all inbound except `allowed_ip_range`; ACCEPT all outbound
- **Static IP:** 1 public IPv4 per instance (included in Linode plan)

#### Storage

| Name | Type | Size | Purpose |
|------|------|------|---------|
| boot-gateway | Boot disk | 25GB | OS + gateway services |
| terraform-state | Linode Object Storage | — | Remote Terraform state (S3-compatible backend) |

---

## DNS

- **Domain registrar(s):** TBD
- **Authoritative DNS provider:** TBD (Cloudflare recommended — free, AU PoP)
- **Domains:**

| Domain | Purpose | DNS managed by |
|--------|---------|----------------|
| TBD | Public static site | TBD |

---

## Secrets & Identity

- **Secret manager:** None — secrets in `secrets/` (gitignored), restricted permissions
- **SSO / identity provider:** None
- **Certificate authority:** Let's Encrypt via ACME (certbot or caddy auto-TLS)

---

## CI/CD & Source Control

- **Git hosting:** GitHub
- **CI/CD platform:** GitHub Actions
- **Container registry:** Docker Hub / GHCR

---

## Monitoring & Observability

- **Log aggregation:** Loki (on gateway)
- **Metrics:** VictoriaMetrics (on gateway)
- **Traces:** Tempo (on gateway)
- **Dashboards:** Grafana (on gateway)
- **Collector agent:** otelcol-contrib (built into custom Alpine image via Packer/Ansible)
- **Alerting:** Grafana Alerts → TBD

---

## Tunnels & Remote Access

- **VPN:** WireGuard (on gateway) — MikroTik home router peers as a client for DNS filtering and admin access
- **Reverse tunnels:** None
- **Jump / bastion host:** gateway doubles as SSH jump host

---

## Service Port Reference

| Service | Port | Protocol | Exposed |
|---------|------|----------|---------|
| WireGuard | 51820 | UDP | Firewall-restricted (allowed_ip_range) |
| SSH | 22 | TCP | Firewall-restricted (allowed_ip_range) |
| Blocky DNS | 53 | UDP/TCP | VPN only |
| Grafana | 3000 | TCP | VPN only |
| Loki | 3100 | TCP | VPN only |
| Tempo gRPC | 4317 | TCP | VPN only |
| Tempo HTTP | 4318 | TCP | VPN only |
| VictoriaMetrics | 8428 | TCP | VPN only |
| otelcol-contrib (health) | 13133 | TCP | localhost only |

---

## Cost Summary

| Resource | Provider | Monthly Cost |
|----------|----------|-------------|
| gateway (g6-nanode-1) | Linode | ~$5 USD |
| Linode Object Storage (state) | Linode | ~$0–1 USD |
| **Total** | | **~$5–6 USD** |
