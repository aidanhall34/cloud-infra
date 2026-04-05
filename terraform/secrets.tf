# Secrets are read from the secrets/ directory (gitignored, never committed).
#
# For CI/CD: write the secret files before running terraform, e.g.:
#   echo "$WG_PRIVATE_KEY"  > ../secrets/wireguard_gateway_private.key
#   echo "$MIKROTIK_PUBKEY" > ../secrets/wireguard_mikrotik_public.key
#
# STATE FILE NOTE: Terraform stores resource attributes in the state file,
# including user_data (the cloud-init blob). The secrets embedded in cloud-init
# will therefore be present in terraform.tfstate, base64-encoded. The state file
# is gitignored and should be treated as sensitive. If using remote state
# (e.g. OCI Object Storage), ensure server-side encryption is enabled.
# The sensitive() wrapper below prevents these values from appearing in
# plan/apply terminal output and logs — it does not exclude them from state.

locals {
  # WireGuard private key for vm-gateway (Curve25519, base64).
  # Public key is derived on-instance; only the private key is stored here.
  wireguard_private_key = sensitive(trimspace(file("${path.root}/../secrets/wireguard_gateway_private.key")))

  # MikroTik router WireGuard public key.
  # Not sensitive, but co-located with other secrets for consistency.
  # If the file still contains the placeholder comment (starts with #),
  # returns "" — the wg0.conf [Peer] section will be left commented out.
  _mikrotik_key_raw             = trimspace(file("${path.root}/../secrets/wireguard_mikrotik_public.key"))
  wireguard_mikrotik_public_key = startswith(local._mikrotik_key_raw, "#") ? "" : local._mikrotik_key_raw

  # Grafana GitHub OAuth credentials.
  # If the file still contains the placeholder comment (starts with #),
  # returns "" — Grafana will start but GitHub OAuth will be inactive.
  _grafana_client_id_raw       = trimspace(file("${path.root}/../secrets/grafana_github_client_id"))
  _grafana_client_secret_raw   = trimspace(file("${path.root}/../secrets/grafana_github_client_secret"))
  grafana_github_client_id     = sensitive(startswith(local._grafana_client_id_raw, "#") ? "" : local._grafana_client_id_raw)
  grafana_github_client_secret = sensitive(startswith(local._grafana_client_secret_raw, "#") ? "" : local._grafana_client_secret_raw)

  # Grafana session signing key — 64-char random hex, generated once by `make generate-grafana-key`.
  grafana_secret_key = sensitive(trimspace(file("${path.root}/../secrets/grafana_secret_key")))

  # Telemetry S3 credentials — OCI Customer Secret Keys used by Loki, Tempo, and vmbackup.
  # Generate at: OCI Console → Profile → User Settings → Customer Secret Keys.
  # If still a placeholder (starts with #), returns "" — services will fail to start.
  _telemetry_s3_access_key_raw = trimspace(file("${path.root}/../secrets/telemetry_s3_access_key"))
  _telemetry_s3_secret_key_raw = trimspace(file("${path.root}/../secrets/telemetry_s3_secret_key"))
  telemetry_s3_access_key      = sensitive(startswith(local._telemetry_s3_access_key_raw, "#") ? "" : local._telemetry_s3_access_key_raw)
  telemetry_s3_secret_key      = sensitive(startswith(local._telemetry_s3_secret_key_raw, "#") ? "" : local._telemetry_s3_secret_key_raw)
}
