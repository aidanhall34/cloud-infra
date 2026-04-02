# Cloud Infrastructure

> **Cost goal: minimise above all else.** Target $0/month (Oracle Always Free).
> Ceiling ~$10/month if fallback hardware is required. Availability and redundancy are not priorities.

## Cloud Providers

### Oracle Cloud — ap-sydney-1 (Sydney)
- **Account type:** Always Free (upgrade to Pay-As-You-Go to prevent idle reclamation — no charges, just unlocks capacity)
- **Primary region:** ap-sydney-1 (Sydney)
- **Notes:** ARM capacity in Sydney can have provisioning delays ("Out of Host Capacity") — retry or script the provisioning. All services run ARM-compatible builds.

#### Compute

| Name / ID | Type | vCPU | RAM | OS | Role |
|-----------|------|------|-----|----|------|
| vm-gateway | E2.1.Micro (x86) | 0.125 OCPU | 1GB | Ubuntu 24.04 LTS | Pi-hole, WireGuard, Nginx |
| vm-telemetry | A1.Flex (ARM) | 4 OCPU | 24GB | Ubuntu 24.04 LTS | Loki, Grafana, Tempo, VictoriaMetrics |

#### Storage

| Name / ID | Type | Size | Purpose |
|-----------|------|------|---------|
| boot-gateway | Boot volume (block) | 50GB | OS + gateway services |
| boot-telemetry | Boot volume (block) | 150GB | OS + LGTM data |

- **Total free block storage pool:** 200GB (shared across all boot volumes)

#### Networking

- **Static IPs / Elastic IPs:** 1 reserved public IP per VM (free on Oracle)
- **VPC / VNet setup:** Single VCN, two public subnets (one per VM)
- **Firewall / Security Groups:** Security lists — open ports per service port table below
- **DNS zones managed here:** None (external — see DNS section)

#### Other services in use

| Service | Name / ID | Purpose |
|---------|-----------|---------|
| Object Storage | (future) | VictoriaMetrics long-term backup via vmbackup (optional) |

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

- **Secret manager:** None initially — secrets in environment files, restricted permissions
- **SSO / identity provider:** None
- **Certificate authority:** Let's Encrypt via ACME (certbot or caddy auto-TLS)

---

## CI/CD & Source Control

- **Git hosting:** GitHub
- **CI/CD platform:** None initially
- **Container registry:** Docker Hub (public images) / GHCR

---

## Monitoring & Observability

- **Log aggregation:** Loki (on vm-telemetry)
- **Metrics:** VictoriaMetrics (on vm-telemetry)
- **Traces:** Tempo (on vm-telemetry)
- **Dashboards:** Grafana (on vm-telemetry)
- **Collector agent:** otelcol-contrib (native .deb on each cloud VM — see migration plan Phase 5 for journald notes)
- **Alerting:** Grafana Alerts → TBD (email / Telegram / webhook)
- **Scope:** both cloud VMs self-monitor; MikroTik router connects via WireGuard but is not monitored

---

## Tunnels & Remote Access

- **VPN:** WireGuard (on vm-gateway) — MikroTik home router peers as a client for DNS filtering and admin access to cloud services
- **Reverse tunnels:** None
- **Jump / bastion host:** vm-gateway doubles as SSH jump host

---

## Service Port Reference

| Service | Port | Protocol | Exposed |
|---------|------|----------|---------|
| WireGuard | 51820 | UDP | Public |
| Pi-hole DNS | 53 | UDP/TCP | VPN only |
| Pi-hole Web UI | 8080 | TCP | VPN only |
| Nginx (static site) | 80/443 | TCP | Public |
| Grafana | 3000 | TCP | VPN only |
| Loki | 3100 | TCP | VPN only |
| Tempo gRPC | 4317 | TCP | VPN only |
| Tempo HTTP | 4318 | TCP | VPN only |
| VictoriaMetrics | 8428 | TCP | VPN only |
| otelcol-contrib (health check) | 13133 | TCP | localhost only |

---

## Cost Summary

| Resource | Provider | Monthly Cost |
|----------|----------|-------------|
| vm-gateway (E2.1.Micro) | Oracle Always Free | $0 |
| vm-telemetry (A1.Flex 4c/24GB) | Oracle Always Free | $0 |
| Block storage (200GB pool) | Oracle Always Free | $0 |
| Egress (up to 10TB/mo) | Oracle Always Free | $0 |
| **Total** | | **$0** |

**Fallback** if Oracle ARM capacity is unavailable: **Contabo Sydney Cloud VPS 20** (~$9 USD/mo, 6 vCPU / 12GB RAM / 100GB NVMe) — run everything on one box.

---

## Notes

- All monitoring endpoints (Grafana, Loki, Tempo, VictoriaMetrics) are firewalled to WireGuard subnet — not publicly accessible.
- VictoriaMetrics replaces Mimir and Prometheus — single binary, ~5–10x lighter, drop-in Prometheus-compatible remote_write. Grafana connects via standard Prometheus datasource.
- Long-term metric retention: VictoriaMetrics compresses aggressively on-disk. Optional backup: `vmbackup` to Cloudflare R2 (free egress).
