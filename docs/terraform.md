# Terraform Layout

All Terraform configuration lives under [`terraform/`](../terraform/).

## Overview

Two Oracle Cloud Always Free VMs are provisioned in a single VCN:

| VM | Shape | Role |
|---|---|---|
| `vm-gateway` | VM.Standard.E2.1.Micro (x86) | WireGuard VPN, Blocky DNS, Nginx static site, otelcol-contrib |
| `vm-telemetry` | VM.Standard.A1.Flex 4 OCPU/24 GB (ARM64) | VictoriaMetrics, Loki, Tempo, Grafana, otelcol-contrib |

Inter-VM communication uses OCI VCN internal DNS (stable across
`create_before_destroy` replacements) rather than dynamic private IPs.

---

## File Reference

### [`main.tf`](../terraform/main.tf)

Declares the required Terraform version (≥ 1.6), the `oracle/oci` provider,
and the S3-compatible remote backend backed by OCI Object Storage.

| Resource / Block | Line | Notes |
|---|---|---|
| `terraform {}` block | [main.tf:1](../terraform/main.tf#L1) | Version constraint + provider requirements |
| `backend "s3" {}` | [main.tf:18](../terraform/main.tf#L18) | Config supplied at `terraform init -backend-config=../secrets/backend.hcl` |
| `provider "oci"` | [main.tf:21](../terraform/main.tf#L21) | Credentials from `var.*` (written to `terraform.tfvars` by CI) |

Backend config values (endpoint, access/secret keys) are not stored in the
repository. See [`terraform/backend.hcl.example`](../terraform/backend.hcl.example)
and [`Makefile:39`](../Makefile#L39) (`make init`) for usage.

---

### [`variables.tf`](../terraform/variables.tf)

All input variables with defaults. Sensitive values (keys, passwords) are
**not** declared here — they are read from files in `secrets/` by
[`secrets.tf`](#secretstf).

| Variable group | Line | Description |
|---|---|---|
| OCI credentials | [variables.tf:3](../terraform/variables.tf#L3) | tenancy, user, fingerprint, key path, region |
| Instance access | [variables.tf:37](../terraform/variables.tf#L37) | `ssh_public_key` |
| Network | [variables.tf:44](../terraform/variables.tf#L44) | VCN CIDR, subnet CIDRs, WireGuard subnet + port |
| Availability domain | [variables.tf:80](../terraform/variables.tf#L80) | `availability_domain_index` (0-based, try 1 or 2 if capacity unavailable) |
| Image overrides | [variables.tf:87](../terraform/variables.tf#L87) | Pin OCIDs to skip marketplace data-source lookup |
| Application | [variables.tf:104](../terraform/variables.tf#L104) | `static_site_domain` for Nginx + certbot |
| Grafana | [variables.tf:112](../terraform/variables.tf#L112) | `grafana_github_org`, `grafana_admin_user` |
| Component versions | [variables.tf:123](../terraform/variables.tf#L123) | otelcol, VictoriaMetrics, Loki, Tempo |

---

### [`secrets.tf`](../terraform/secrets.tf)

Reads all secrets from the `secrets/` directory (gitignored) into `locals`
wrapped with `sensitive()`. This keeps secret values out of the plan/apply
terminal output. They are still present in Terraform state (base64-encoded
inside the cloud-init `user_data` blob) — the state file itself must be
treated as sensitive.

| Local | Line | Source file |
|---|---|---|
| `wireguard_private_key` | [secrets.tf:19](../terraform/secrets.tf#L19) | `secrets/wireguard_gateway_private.key` |
| `wireguard_mikrotik_public_key` | [secrets.tf:25](../terraform/secrets.tf#L25) | `secrets/wireguard_mikrotik_public.key` (placeholder-aware) |
| `grafana_github_client_id` | [secrets.tf:31](../terraform/secrets.tf#L31) | `secrets/grafana_github_client_id` (placeholder-aware) |
| `grafana_github_client_secret` | [secrets.tf:34](../terraform/secrets.tf#L34) | `secrets/grafana_github_client_secret` (placeholder-aware) |
| `grafana_secret_key` | [secrets.tf:38](../terraform/secrets.tf#L38) | `secrets/grafana_secret_key` |

Placeholder-aware locals return `""` if the file starts with `#`, so an
initial deploy succeeds before OAuth credentials are populated.

---

### [`network.tf`](../terraform/network.tf)

Provisions the full network topology.

| Resource | Line | Notes |
|---|---|---|
| `oci_core_vcn.homelab` | [network.tf:11](../terraform/network.tf#L11) | VCN with `dns_label = "homelab"` |
| `oci_core_internet_gateway.homelab` | [network.tf:18](../terraform/network.tf#L18) | Internet gateway |
| `oci_core_route_table.public` | [network.tf:25](../terraform/network.tf#L25) | Default route 0.0.0.0/0 → IGW |
| `oci_core_security_list.gateway` | [network.tf:39](../terraform/network.tf#L39) | Allows SSH/22, WireGuard UDP, HTTP/80, HTTPS/443 |
| `oci_core_security_list.telemetry` | [network.tf:78](../terraform/network.tf#L78) | Allows SSH/22, all traffic from VCN CIDR + WireGuard subnet |
| `oci_core_subnet.gateway` | [network.tf:113](../terraform/network.tf#L113) | `dns_label = "gateway"` — used in OCI VCN hostname |
| `oci_core_subnet.telemetry` | [network.tf:123](../terraform/network.tf#L123) | `dns_label = "telemetry"` — used in OCI VCN hostname |

The `dns_label` values on the VCN and subnets form the stable internal
hostname: `vm-telemetry.telemetry.homelab.oraclevcn.com`. This is why
inter-VM routing does not rely on dynamic private IPs.

---

### [`compute.tf`](../terraform/compute.tf)

Image lookup and instance resources.

| Resource / Local | Line | Notes |
|---|---|---|
| `data "oci_core_images" ubuntu_amd64` | [compute.tf:5](../terraform/compute.tf#L5) | Latest Ubuntu 24.04 Minimal for E2.1.Micro |
| `data "oci_core_images" ubuntu_arm64` | [compute.tf:15](../terraform/compute.tf#L15) | Latest Ubuntu 24.04 Minimal aarch64 for A1.Flex |
| `local.telemetry_internal_hostname` | [compute.tf:33](../terraform/compute.tf#L33) | Stable OCI VCN DNS hostname for vm-telemetry |
| `data "cloudinit_config" "gateway"` | [compute.tf:46](../terraform/compute.tf#L46) | Assembles common + gateway cloud-init as MIME multipart |
| `data "cloudinit_config" "telemetry"` | [compute.tf:77](../terraform/compute.tf#L77) | Assembles common + telemetry cloud-init as MIME multipart |
| `oci_core_instance.gateway` | [compute.tf:124](../terraform/compute.tf#L124) | vm-gateway, `create_before_destroy = true` (2x E2.1.Micro fits free tier) |
| `oci_core_instance.telemetry` | [compute.tf:162](../terraform/compute.tf#L162) | vm-telemetry, `create_before_destroy = true` (see warning: ARM free pool is shared) |

Cloud-init is assembled by `data "cloudinit_config"` blocks which merge `common.yaml.tpl`
and the VM-specific template as MIME multipart. Each instance references
`data.cloudinit_config.<vm>.rendered` in its `user_data` metadata field.
Secrets are passed from `locals` in `secrets.tf`, never from direct variable values.

---

### [`outputs.tf`](../terraform/outputs.tf)

| Output | Line | Notes |
|---|---|---|
| `gateway_public_ip` | [outputs.tf:1](../terraform/outputs.tf#L1) | Use as WireGuard endpoint in MikroTik |
| `telemetry_public_ip` | [outputs.tf:6](../terraform/outputs.tf#L6) | SSH access only |
| `gateway_private_ip` | [outputs.tf:11](../terraform/outputs.tf#L11) | Informational — changes on recreation |
| `telemetry_private_ip` | [outputs.tf:16](../terraform/outputs.tf#L16) | Informational — changes on recreation |
| `wireguard_gateway_public_key` | [outputs.tf:21](../terraform/outputs.tf#L21) | WireGuard public key for MikroTik peer config |
| `next_steps` | [outputs.tf:26](../terraform/outputs.tf#L26) | Post-deploy checklist with SSH commands |

---

### [`cloud-init/gateway.yaml.tpl`](../terraform/cloud-init/gateway.yaml.tpl)

Cloud-init template for `vm-gateway`. Assembled into MIME multipart by
[`data "cloudinit_config" "gateway"`](../terraform/compute.tf#L46) in `compute.tf`.

Key sections:

| Section | Description |
|---|---|
| `write_files` — WireGuard private key | Written to `/etc/wireguard/private.key` (`0600`) |
| `write_files` — `wireguard-setup.sh` | Derives public key, builds `wg0.conf` with MikroTik peer (conditional on `${wireguard_mikrotik_public_key}`) |
| `write_files` — `/etc/blocky/adlists.txt` | Denylist URLs from `config/dns/adlists.txt` |
| `write_files` — `/etc/blocky/allowlist.txt` | Allowlisted domains from `config/dns/allowlist.txt` |
| `write_files` — `/etc/blocky/local_dns.txt` | Custom DNS records from `config/dns/local_dns.txt` |
| `write_files` — `blocky-generate-config.sh` | Generates `/etc/blocky/config.yaml` from the three provisioned files |
| `write_files` — otelcol config | Forwards host metrics + Blocky Prometheus metrics + journald logs to `${telemetry_hostname}` |
| `runcmd` | Installs and starts WireGuard, Blocky DNS, Nginx, otelcol-contrib |

Template variables: `telemetry_hostname`, `wireguard_subnet`, `wireguard_port`,
`wireguard_private_key`, `wireguard_mikrotik_public_key`, `static_site_domain`,
`blocky_version`, `blocky_adlists`, `blocky_allowlist`, `blocky_local_dns`,
`otelcol_version`.

---

### [`cloud-init/telemetry.yaml.tpl`](../terraform/cloud-init/telemetry.yaml.tpl)

Cloud-init template for `vm-telemetry`. Assembled into MIME multipart by
[`data "cloudinit_config" "telemetry"`](../terraform/compute.tf#L77) in `compute.tf`.

Key sections:

| Section | Description |
|---|---|
| `write_files` — Grafana `grafana.ini` | GitHub OAuth config, session key, disable default admin + login form |
| `write_files` — Grafana datasources | Provisions VictoriaMetrics, Loki, Tempo as datasources with trace-to-log correlation |
| `write_files` — VictoriaMetrics service | Systemd unit, 12-month retention, port 8428 |
| `write_files` — Loki config + service | Filesystem storage, TSDB schema v13, 90-day retention, port 3100 |
| `write_files` — Tempo config + service | OTLP gRPC/HTTP receivers, 30-day trace retention, port 3200 |
| `write_files` — otelcol config | Collects host metrics + journald logs, exports to localhost VictoriaMetrics + Loki + Tempo |
| `runcmd` | Downloads and installs all binaries; installs Grafana from apt repo |

Template variables: `otelcol_version`, `victoriametrics_version`, `loki_version`,
`tempo_version`, `grafana_github_client_id`, `grafana_github_client_secret`,
`grafana_secret_key`, `grafana_github_org`, `grafana_admin_user`.

---

## Updating this document

When a resource is added, removed, or its start line changes materially,
update the relevant table row's line number link. The convention is
`[filename:N](../path/to/file#LN)` which renders as a clickable GitHub link.
