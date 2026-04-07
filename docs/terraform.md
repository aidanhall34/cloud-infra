# Terraform Layout

All Terraform configuration lives under [`terraform/`](../terraform/).

## Overview

A single Linode instance (`gateway`) is provisioned in `ap-southeast` (Singapore) with a firewall that only accepts inbound traffic from a configured IP range.

| Resource | Type | Role |
|---|---|---|
| `gateway` | Linode g6-nanode-1 (x86_64) | WireGuard VPN, Blocky DNS, Nginx, otelcol-contrib |
| `firewall` | Linode Cloud Firewall | DROP all inbound except `var.allowed_ip_range`; ACCEPT all outbound |

The gateway is deployed from the latest custom Alpine image built by Packer (`make packer-build-gateway`). The image is resolved automatically at plan time via a data source — no image ID variable is required.

---

## First-time Setup

```bash
# 1. Create the Terraform state bucket in Linode Object Storage (idempotent — skips if already exists):
make tf-init-bucket

# 2. Copy and populate the variable values:
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform/terraform.tfvars  (set ssh_public_key, allowed_ip_range, etc.)

# 3. Build the gateway image (must run before plan — the data source resolves it at plan time):
make packer-build-gateway

# 4. Initialise, plan, and deploy — temporary Linode tokens and OBJ keys are created automatically:
make tf-init
make tf-plan
make tf-deploy
```

---

## File Reference

### [`main.tf`](../terraform/main.tf)

Declares the required Terraform version (≥ 1.6), the `linode/linode` provider, and the S3-compatible remote backend backed by Linode Object Storage.

| Block | Notes |
|---|---|
| `terraform {}` | Version constraint + provider requirements |
| `backend "s3" {}` | Bucket, endpoint, and region are hardcoded; access keys are injected at runtime via `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` env vars |
| `provider "linode"` | Authenticated via `var.linode_token` |

Backend credentials are never stored in the repository. `make tf-init`, `make tf-plan`, and `make tf-deploy` each create a short-lived OBJ key automatically and delete it on exit.

---

### [`data.tf`](../terraform/data.tf)

Resolves the latest gateway image at plan time.

| Data source | Notes |
|---|---|
| `linode_images.gateway` | Filters private images whose label contains `alpine-gateway-`, selects the newest (`latest = true`) |

Images are labelled `alpine-gateway-<alpine_version>-<git_sha>` by Packer. Running `make packer-build-gateway` before `make tf-plan` ensures the latest image is picked up automatically.

---

### [`variables.tf`](../terraform/variables.tf)

| Variable | Type | Default | Description |
|---|---|---|---|
| `linode_token` | string | — | API token (sensitive). Set via `TF_VAR_linode_token` or `terraform.tfvars` |
| `linode_region` | string | `ap-southeast` | Linode region |
| `instance_type` | string | `g6-nanode-1` | Linode plan for the gateway |
| `ssh_public_key` | string | — | SSH public key injected into the instance |
| `allowed_ip_range` | string | — | CIDR block that may send inbound traffic (all else is DROPped) |

---

### [`network.tf`](../terraform/network.tf)

Provisions a Linode Cloud Firewall and attaches it to the gateway instance.

| Resource | Notes |
|---|---|
| `linode_firewall.gateway` | Inbound: ACCEPT TCP + UDP (all ports) + ICMP from `allowed_ip_range`; default inbound policy: DROP; outbound policy: ACCEPT |

To temporarily unlock access from a different IP without re-running Terraform, edit the firewall in the Linode Cloud Manager and re-apply to restore the IaC state.

---

### [`compute.tf`](../terraform/compute.tf)

| Resource | Notes |
|---|---|
| `linode_instance.gateway` | Image resolved from `data.linode_images.gateway`, `create_before_destroy = true` |

---

### [`outputs.tf`](../terraform/outputs.tf)

| Output | Description |
|---|---|
| `gateway_public_ip` | Public IPv4 — use as the WireGuard endpoint in MikroTik |
| `gateway_id` | Linode instance ID |

---

## Credentials Pattern

Sensitive values follow this hierarchy — never commit any of these files:

| File / env var | Purpose |
|---|---|
| `terraform/terraform.tfvars` | Variable overrides: `linode_token`, `ssh_public_key`, `allowed_ip_range` |
| `TF_VAR_linode_token` | Alternative to tfvars — avoids writing the token to disk |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | OBJ backend credentials — injected automatically by `make tf-*` targets, never stored |

---

## Updating this Document

When a resource is added, removed, or its role changes materially, update the relevant table row. The convention is `[filename:N](../path/to/file#LN)` which renders as a clickable GitHub link.
