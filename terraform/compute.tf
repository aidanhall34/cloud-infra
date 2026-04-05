# --- Image lookup ---
# gateway: requires a custom Alpine image built with packer/gateway.pkr.hcl.
#          Set gateway_image_ocid to the OCID returned by `make packer-build-gateway`.
# telemetry: auto-selects the latest Ubuntu 24.04 Minimal (ARM64) from the marketplace,
#            or use telemetry_image_ocid to pin a specific version.

data "oci_core_images" "ubuntu_arm64" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04 Minimal aarch64"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"
}

locals {
  # gateway_image_id uses the custom Alpine Packer image — no Ubuntu fallback.
  gateway_image_id   = var.gateway_image_ocid
  telemetry_image_id = var.telemetry_image_ocid != "" ? var.telemetry_image_ocid : data.oci_core_images.ubuntu_arm64.images[0].id

  # OCI VCN internal DNS hostnames — stable across instance replacements
  # because they are derived from the dns_label values set in network.tf,
  # not from dynamic private IPs. This is what enables create_before_destroy.
  # Format: <hostname_label>.<subnet_dns_label>.<vcn_dns_label>.oraclevcn.com
  telemetry_internal_hostname = "vm-telemetry.${oci_core_subnet.telemetry.dns_label}.${oci_core_vcn.homelab.dns_label}.oraclevcn.com"

  # Derived S3 settings passed to the telemetry cloud-init template.
  # Loki and Tempo take endpoint as host[:port] without scheme; insecure=true for http.
  telemetry_s3_endpoint_host = replace(replace(var.telemetry_s3_endpoint, "https://", ""), "http://", "")
  telemetry_s3_insecure      = var.telemetry_s3_endpoint != "" ? startswith(var.telemetry_s3_endpoint, "http://") : false
}

# --- cloud-init assembly (common + VM-specific merged as MIME multipart) ---
# The cloudinit provider combines the shared base config with each VM's specific
# config. list(append)+dict(recurse_array) on the VM part ensures packages,
# runcmd, and write_files arrays are concatenated (not replaced).

data "cloudinit_config" "gateway" {
  gzip          = false
  base64_encode = true

  part {
    filename     = "common.yaml"
    content_type = "text/cloud-config"
    content      = file("${path.module}/cloud-init/common.yaml.tpl")
  }

  part {
    filename     = "gateway.yaml"
    content_type = "text/cloud-config"
    merge_type   = "list(append)+dict(recurse_array)+str()"
    content = templatefile("${path.module}/cloud-init/gateway.yaml.tpl", {
      telemetry_hostname            = local.telemetry_internal_hostname
      wireguard_port                = var.wireguard_port
      wireguard_private_key         = local.wireguard_private_key
      wireguard_mikrotik_public_key = local.wireguard_mikrotik_public_key
      blocky_adlists                = file("${path.module}/../config/dns/adlists.txt")
      blocky_allowlist              = file("${path.module}/../config/dns/allowlist.txt")
      blocky_local_dns              = file("${path.module}/../config/dns/local_dns.txt")
    })
  }
}

data "cloudinit_config" "telemetry" {
  gzip          = false
  base64_encode = true

  part {
    filename     = "common.yaml"
    content_type = "text/cloud-config"
    content      = file("${path.module}/cloud-init/common.yaml.tpl")
  }

  part {
    filename     = "telemetry.yaml"
    content_type = "text/cloud-config"
    merge_type   = "list(append)+dict(recurse_array)+str()"
    content = templatefile("${path.module}/cloud-init/telemetry.yaml.tpl", {
      victoriametrics_version      = var.victoriametrics_version
      loki_version                 = var.loki_version
      tempo_version                = var.tempo_version
      grafana_github_client_id     = local.grafana_github_client_id
      grafana_github_client_secret = local.grafana_github_client_secret
      grafana_secret_key           = local.grafana_secret_key
      grafana_github_org           = var.grafana_github_org
      grafana_admin_user           = var.grafana_admin_user
      grafana_oauth_auth_url       = var.grafana_oauth_auth_url
      grafana_oauth_token_url      = var.grafana_oauth_token_url
      grafana_oauth_api_url        = var.grafana_oauth_api_url
      telemetry_s3_endpoint        = var.telemetry_s3_endpoint
      telemetry_s3_endpoint_host   = local.telemetry_s3_endpoint_host
      telemetry_s3_insecure        = local.telemetry_s3_insecure
      telemetry_s3_region          = var.telemetry_s3_region
      telemetry_s3_bucket_loki     = var.telemetry_s3_bucket_loki
      telemetry_s3_bucket_tempo    = var.telemetry_s3_bucket_tempo
      telemetry_s3_bucket_vmbackup = var.telemetry_s3_bucket_vmbackup
      telemetry_s3_access_key      = local.telemetry_s3_access_key
      telemetry_s3_secret_key      = local.telemetry_s3_secret_key
    })
  }
}

# --- vm-gateway (E2.1.Micro, x86, Always Free) ---
# Runs: WireGuard, Blocky DNS, Nginx, otelcol-contrib
#
# create_before_destroy: OCI Always Free allows 2x E2.1.Micro, so a temporary
# second instance fits within the free tier during replacement.

resource "oci_core_instance" "gateway" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = "vm-gateway"
  shape               = "VM.Standard.E2.1.Micro"

  lifecycle {
    create_before_destroy = true
  }

  source_details {
    source_type             = "image"
    source_id               = local.gateway_image_id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.gateway.id
    display_name     = "gateway-vnic"
    assign_public_ip = true
    hostname_label   = "vm-gateway"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = data.cloudinit_config.gateway.rendered
  }
}

# --- vm-telemetry (A1.Flex, ARM64, Always Free) ---
# Runs: VictoriaMetrics, Loki, Tempo, Grafana, otelcol-contrib
#
# create_before_destroy: NOTE — the Always Free ARM pool is 4 OCPUs / 24 GB total.
# A replacement would temporarily require 8 OCPUs / 48 GB, exceeding the free tier.
# Terraform will attempt create_before_destroy but OCI may reject with "Out of Capacity".
# If this happens, destroy the old instance manually first, then apply.
# Alternatively, set create_before_destroy = false on this resource during replacement.

resource "oci_core_instance" "telemetry" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = "vm-telemetry"
  shape               = "VM.Standard.A1.Flex"

  lifecycle {
    create_before_destroy = true
  }

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  source_details {
    source_type             = "image"
    source_id               = local.telemetry_image_id
    boot_volume_size_in_gbs = 150
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.telemetry.id
    display_name     = "telemetry-vnic"
    assign_public_ip = true
    hostname_label   = "vm-telemetry"
  }

  # Buckets must exist before the VM boots — Loki, Tempo, and vmbackup will
  # fail to start if the S3 destination is not reachable on first boot.
  depends_on = [
    oci_objectstorage_bucket.loki,
    oci_objectstorage_bucket.tempo,
    oci_objectstorage_bucket.vmbackup,
  ]

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = data.cloudinit_config.telemetry.rendered
  }
}
