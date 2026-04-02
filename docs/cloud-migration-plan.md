# Cloud Infrastructure Plan

## Overarching Goal

**Minimise cost above all else.** Every architectural decision should prefer the cheapest viable option.
Availability, redundancy, and operational complexity are secondary concerns — this is a personal homelab.
Target: $0/month on Oracle Always Free. Absolute ceiling: ~$10/month if fallback hardware is needed.

See `cloud-infrastructure.md` for provider decisions and cost breakdown.

## Status Legend
- [ ] Not started
- [~] In progress
- [x] Done

---

## Deploying

### First-time setup

```bash
# 1. Create OCI Object Storage bucket for Terraform state (one-time, manual):
#    OCI Console → Object Storage → Buckets → Create Bucket
#    Name: terraform-state | Region: ap-sydney-1 | Visibility: Private

# 2. Upload all secrets to GitHub:
./scripts/upload-secrets.sh

# 3. Push to GitHub, then:
#    GitHub → Actions → Deploy Infrastructure → Run workflow → plan
#    Review plan output, then run again with → apply
```

### Subsequent deployments

```
GitHub → Actions → Deploy Infrastructure → Run workflow → apply
```

### Local runs (optional)

```bash
cp terraform/backend.hcl.example secrets/backend.hcl
# fill in secrets/backend.hcl, terraform/terraform.tfvars, secrets/*.key

cd terraform
terraform init -backend-config=../secrets/backend.hcl
terraform plan
terraform apply
```

If `terraform apply` fails with "Out of Host Capacity" on the A1.Flex instance,
set `availability_domain_index = 1` (or `2`) in `terraform.tfvars` and retry.

---

## Phase 1 — Oracle Cloud Account & Networking

- [ ] Create Oracle Cloud account, set home region to **ap-sydney-1**
- [ ] Upgrade to Pay-As-You-Go (no charges — required to prevent idle reclamation of free instances)
- [ ] Collect credentials for `terraform.tfvars`: tenancy OCID, user OCID, API key + fingerprint, SSH public key
- [x] ~~Create VCN, subnets, security lists, route table~~ — handled by `terraform/network.tf`

---

## Phase 2 — Provision VMs

- [x] ~~Provision vm-gateway and vm-telemetry~~ — handled by `terraform/compute.tf` + cloud-init
- [ ] `terraform apply` completes successfully
- [ ] SSH access confirmed for both VMs
- [ ] cloud-init finished on both VMs (`sudo cloud-init status --wait`)

---

## Phase 3 — vm-gateway Services

### WireGuard VPN
- [ ] Install WireGuard
- [ ] Generate server keypair
- [ ] Configure `wg0` interface (assign VPN subnet, e.g. `10.10.0.0/24`)
- [ ] Enable IP forwarding + NAT (iptables / nftables)
- [ ] Configure MikroTik router as WireGuard peer
  - [ ] Add WireGuard interface on MikroTik
  - [ ] Set vm-gateway public IP as endpoint
  - [ ] Add routes for VPN subnet
  - [ ] Test tunnel up/down

### Pi-hole
- [ ] Install Pi-hole (Docker or native)
- [ ] Bind DNS to WireGuard interface only (not public IP)
- [ ] Configure upstream DNS (e.g. Cloudflare 1.1.1.1 or DNS-over-HTTPS)
- [ ] Point MikroTik DNS to Pi-hole VPN IP
- [ ] Verify DNS filtering working

### Nginx (static site)
- [ ] Install Nginx
- [ ] Configure site root and basic server block
- [ ] Obtain TLS cert via Let's Encrypt (certbot)
- [ ] Deploy initial static HTML content
- [ ] Verify public HTTPS access

---

## Phase 4 — vm-telemetry Services (LGTM stack)

All services on this VM are ARM (aarch64) — verify image tags support `linux/arm64`.

### VictoriaMetrics
- [ ] Deploy VictoriaMetrics single-node binary (or Docker)
- [ ] Configure retention period (recommend 1 year)
- [ ] Expose on `0.0.0.0:8428` (firewalled to WireGuard subnet)
- [ ] Test remote_write endpoint with curl

### Loki
- [ ] Deploy Loki (single-binary / monolithic mode)
- [ ] Configure local filesystem storage
- [ ] Expose on port 3100 (WireGuard only)

### Tempo
- [ ] Deploy Tempo (single-binary mode)
- [ ] Configure OTLP gRPC (4317) and HTTP (4318) receivers
- [ ] Expose on WireGuard subnet only

### Grafana
- [ ] Deploy Grafana
- [ ] Configure datasources:
  - [ ] VictoriaMetrics (Prometheus-compatible, `http://localhost:8428`)
  - [ ] Loki (`http://localhost:3100`)
  - [ ] Tempo (`http://localhost:4317`)
- [ ] Expose on port 3000 (WireGuard only)
- [ ] Set admin password, disable anonymous access

---

## Phase 5 — Telemetry Agents (otelcol-contrib)

Deploy `otelcol-contrib` on each cloud VM to ship metrics, logs, and traces to vm-telemetry.

### Collector: otelcol-contrib (native .deb install)

Install as a native systemd service — **not** Docker. The `journaldreceiver` works by shelling out to
the `journalctl` binary. The official Docker image is missing `journalctl` and the upstream project has
closed the request to add it ("Not Planned"). Running natively avoids this entirely.

**Install (amd64, vm-gateway):**
```bash
VERSION="0.149.0"  # check https://github.com/open-telemetry/opentelemetry-collector-releases/releases
wget "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${VERSION}/otelcol-contrib_${VERSION}_linux_amd64.deb"
sudo dpkg -i otelcol-contrib_${VERSION}_linux_amd64.deb
```

**Install (arm64, vm-telemetry):**
```bash
wget "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${VERSION}/otelcol-contrib_${VERSION}_linux_arm64.deb"
sudo dpkg -i otelcol-contrib_${VERSION}_linux_arm64.deb
```

**journald group permission (both VMs):**
```bash
sudo usermod -aG systemd-journal otelcol-contrib
sudo systemctl restart otelcol-contrib
```

**Config location:** `/etc/otelcol-contrib/config.yaml`

**Receivers per host:**
- `hostmetrics` — CPU, memory, disk, network
- `journald` — systemd journal logs
- `prometheus` — scrape Pi-hole metrics endpoint (vm-gateway only)

**Exporters:** OTLP to vm-telemetry WireGuard IP:
- Metrics → VictoriaMetrics (prometheusremotewrite to `:8428`)
- Logs → Loki (loki exporter to `:3100`)
- Traces → Tempo (otlp to `:4317`)

### Alternative: Docker custom image

If Docker uniformity is preferred, build from `debian:12-slim` (not the official distroless image).
Add `apt install systemd` to get `journalctl`, install the otelcol-contrib tarball, mount
`/var/log/journal` and `/run/log/journal` read-only, and add the container user to the host's
`systemd-journal` group. See [upstream example Dockerfile](https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/receiver/journaldreceiver/examples/container).

### Deploy checklist

- [ ] Deploy otelcol-contrib on **vm-gateway** (amd64, native)
  - [ ] Add `otelcol-contrib` to `systemd-journal` group
  - [ ] Configure hostmetrics + journald + prometheus (Pi-hole) receivers
- [ ] Deploy otelcol-contrib on **vm-telemetry** (arm64, native)
  - [ ] Add `otelcol-contrib` to `systemd-journal` group
  - [ ] Configure hostmetrics + journald receivers
- [ ] Verify metrics appearing in Grafana for both hosts
- [ ] Verify logs appearing in Loki for both hosts

---

## Phase 6 — Dashboards & Alerting

- [ ] Import Node Exporter / system metrics dashboard
- [ ] Import Loki logs dashboard
- [ ] Create Pi-hole metrics dashboard (scraped via otelcol-contrib prometheus receiver on vm-gateway)
- [ ] Create WireGuard peers dashboard
- [ ] Configure alerting contact point (email / Telegram / webhook)
- [ ] Set up basic alerts:
  - [ ] Host down (heartbeat)
  - [ ] Disk usage > 80%
  - [ ] High memory usage

---

## Phase 7 — Validation

- [ ] All services reachable via WireGuard
- [ ] DNS filtering confirmed working
- [ ] Static site publicly accessible over HTTPS
- [ ] Grafana showing data from both cloud hosts
- [ ] Alerts tested (fire a test alert, confirm delivery)
- [ ] Document final IPs, ports, and credentials location in cloud-infrastructure.md

---

## Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-04-01 | Oracle Cloud (ap-sydney-1) as primary provider | Always Free tier; Sydney region; 4c/24GB ARM + 1GB x86 at $0/mo |
| 2026-04-01 | Contabo Sydney Cloud VPS 20 (~$9/mo) as fallback | Best paid value in AU if Oracle ARM capacity unavailable; 6c/12GB for $9/mo |
| 2026-04-01 | VictoriaMetrics instead of Mimir | Single binary, 5–10x lower resource usage, drop-in Prometheus-compatible |
| 2026-04-01 | VictoriaMetrics instead of Prometheus+Thanos | Built-in long-term retention with better compression; no extra components |
| 2026-04-01 | All telemetry endpoints VPN-only | Security — no monitoring infrastructure exposed publicly |
| 2026-04-01 | otelcol-contrib as collector (native .deb, not Docker) | journaldreceiver needs journalctl binary — official Docker image missing it, upstream closed the request as "Not Planned" |
| 2026-04-01 | No on-prem hardware in scope | Everything runs in cloud; MikroTik router connects via WireGuard for DNS filtering only |
