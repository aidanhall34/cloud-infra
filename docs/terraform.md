# Terraform Layout

All Terraform configuration lives under [`terraform/`](../terraform/).

## Overview

A single Linode instance (`vm-gateway`) is provisioned in `ap-southeast` (Singapore) with a firewall that only accepts inbound traffic from a configured IP range.

| Resource | Type | Role |
|---|---|---|
| `gateway` | Linode g6-nanode-1 (x86_64) | WireGuard VPN, Blocky DNS, Nginx, otelcol-contrib |
| `firewall` | Linode Cloud Firewall | DROP all inbound except `var.allowed_ip_range`; ACCEPT all outbound |

The gateway is deployed from a custom Alpine image built by Packer (`make packer-build-gateway`).

---

## First-time Setup

```bash
# 1. Build the gateway image and note its Linode image ID:
make packer-build-gateway

# 2. Create a Terraform backend bucket in Linode Object Storage (one-time, manual):
#    https://cloud.linode.com/object-storage/buckets

# 3. Copy and populate the backend config:
cp terraform/backend.hcl.example secrets/backend.hcl
# edit secrets/backend.hcl

# 4. Copy and populate the variable values:
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# edit terraform/terraform.tfvars  (set gateway_image, ssh_public_key, allowed_ip_range, etc.)

# 5. Generate a deploy token (24-hour expiry):
make linode-deploy-token   # copy the token value into terraform.tfvars or TF_VAR_linode_token

# 6. Initialise and deploy:
make tf-init
make tf-plan
make tf-apply
```

---

## File Reference

### [`main.tf`](../terraform/main.tf)

Declares the required Terraform version (≥ 1.6), the `linode/linode` provider, and the S3-compatible remote backend backed by Linode Object Storage.

| Block | Notes |
|---|---|
| `terraform {}` | Version constraint + provider requirements |
| `backend "s3" {}` | Config supplied at `terraform init -backend-config=../secrets/backend.hcl` |
| `provider "linode"` | Authenticated via `var.linode_token` |

Backend config values (endpoint, access/secret keys) are not stored in the repository. See [`terraform/backend.hcl.example`](../terraform/backend.hcl.example) for the required keys.

---

### [`variables.tf`](../terraform/variables.tf)

| Variable | Type | Default | Description |
|---|---|---|---|
| `linode_token` | string | — | API token (sensitive). Set via `TF_VAR_linode_token` or `terraform.tfvars` |
| `linode_region` | string | `ap-southeast` | Linode region |
| `instance_type` | string | `g6-nanode-1` | Linode plan for the gateway |
| `gateway_image` | string | — | Linode image ID from Packer (e.g. `private/12345678`) |
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
| `linode_instance.gateway` | Deployed from `var.gateway_image`, `create_before_destroy = true` |

---

### [`outputs.tf`](../terraform/outputs.tf)

| Output | Description |
|---|---|
| `gateway_public_ip` | Public IPv4 — use as the WireGuard endpoint in MikroTik |
| `gateway_id` | Linode instance ID |

---

## Credentials Pattern

Sensitive values follow this hierarchy — never commit any of these files:

| File | Purpose |
|---|---|
| `secrets/backend.hcl` | Linode Object Storage bucket + access keys for remote state |
| `terraform/terraform.tfvars` | All variable overrides including `linode_token` |

Alternatively, export `TF_VAR_linode_token` in your shell to avoid writing the token to disk.

---

## Updating this Document

When a resource is added, removed, or its line changes materially, update the relevant table row. The convention is `[filename:N](../path/to/file#LN)` which renders as a clickable GitHub link.
