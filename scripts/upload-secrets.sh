#!/usr/bin/env bash
# Uploads all required secrets to a GitHub repository.
#
# Requirements:
#   - gh CLI installed and authenticated: https://cli.github.com/
#   - Run: gh auth login   (if not already authenticated)
#   - secrets/ directory populated (run scripts/generate-secrets.sh first)
#   - ~/.oci/oci_api_key.pem present
#
# Usage:
#   ./scripts/upload-secrets.sh                        # uses current repo
#   ./scripts/upload-secrets.sh owner/repo-name        # explicit repo
#
# Secrets uploaded:
#   OCI credentials     → from interactive prompts (not stored in files)
#   WireGuard keys      → from secrets/ directory
#   State backend       → from interactive prompts

set -euo pipefail

REPO="${1:-}"
REPO_FLAG="${REPO:+--repo $REPO}"

SECRETS_DIR="$(cd "$(dirname "$0")/.." && pwd)/secrets"

# ── Helpers ───────────────────────────────────────────────────────────────────

upload_file() {
  local name="$1"
  local file="$2"
  if [ ! -f "$file" ]; then
    echo "  SKIP $name — file not found: $file"
    return 0
  fi
  # shellcheck disable=SC2086
  gh secret set "$name" $REPO_FLAG < "$file"
  echo "  OK   $name"
}

upload_value() {
  local name="$1"
  local value="$2"
  # shellcheck disable=SC2086
  printf '%s' "$value" | gh secret set "$name" $REPO_FLAG
  echo "  OK   $name"
}

prompt() {
  local var_name="$1"
  local label="$2"
  local silent="${3:-}"
  if [ -n "$silent" ]; then
    read -rsp "  $label: " "$var_name"
    echo
  else
    read -rp  "  $label: " "$var_name"
  fi
}

# ── WireGuard keys ────────────────────────────────────────────────────────────

echo ""
echo "── WireGuard keys ────────────────────────────────────────────────────────"
upload_file WG_GATEWAY_PRIVATE_KEY "$SECRETS_DIR/wireguard_gateway_private.key"
upload_file WG_GATEWAY_PUBLIC_KEY  "$SECRETS_DIR/wireguard_gateway_public.key"

if grep -q '^#' "$SECRETS_DIR/wireguard_mikrotik_public.key" 2>/dev/null; then
  echo "  SKIP WG_MIKROTIK_PUBLIC_KEY — placeholder not yet filled in"
  echo "       Edit secrets/wireguard_mikrotik_public.key with the MikroTik public key,"
  echo "       then re-run this script."
else
  upload_file WG_MIKROTIK_PUBLIC_KEY "$SECRETS_DIR/wireguard_mikrotik_public.key"
fi

# ── Grafana ───────────────────────────────────────────────────────────────────

echo ""
echo "── Grafana GitHub OAuth ──────────────────────────────────────────────────"
if grep -q '^#' "$SECRETS_DIR/grafana_github_client_id" 2>/dev/null; then
  echo "  SKIP GRAFANA_GITHUB_CLIENT_ID — placeholder not yet filled in"
  echo "       Run: scripts/setup-github-oauth.sh"
else
  upload_file GRAFANA_GITHUB_CLIENT_ID     "$SECRETS_DIR/grafana_github_client_id"
  upload_file GRAFANA_GITHUB_CLIENT_SECRET "$SECRETS_DIR/grafana_github_client_secret"
fi
upload_file GRAFANA_SECRET_KEY "$SECRETS_DIR/grafana_secret_key"

# ── OCI API key ───────────────────────────────────────────────────────────────

echo ""
echo "── OCI API key ───────────────────────────────────────────────────────────"
OCI_KEY_FILE="${OCI_KEY_FILE:-$HOME/.oci/oci_api_key.pem}"
if [ ! -f "$OCI_KEY_FILE" ]; then
  echo "  OCI API private key not found at $OCI_KEY_FILE"
  prompt OCI_KEY_FILE "Path to OCI API private key (.pem)"
fi
upload_file OCI_API_PRIVATE_KEY "$OCI_KEY_FILE"

# ── OCI account credentials ───────────────────────────────────────────────────

echo ""
echo "── OCI account credentials ───────────────────────────────────────────────"
echo "  Find these at: OCI Console → Profile (top-right)"
echo ""
prompt tenancy_ocid     "OCI_TENANCY_OCID     (Profile → Tenancy)"
prompt user_ocid        "OCI_USER_OCID        (Profile → User Settings)"
prompt fingerprint      "OCI_FINGERPRINT      (User Settings → API Keys → fingerprint)"
prompt compartment_ocid "OCI_COMPARTMENT_OCID (same as tenancy OCID for root compartment)"
prompt ssh_public_key   "SSH_PUBLIC_KEY       (contents of ~/.ssh/id_ed25519.pub)"

upload_value OCI_TENANCY_OCID     "$tenancy_ocid"
upload_value OCI_USER_OCID        "$user_ocid"
upload_value OCI_FINGERPRINT      "$fingerprint"
upload_value OCI_COMPARTMENT_OCID "$compartment_ocid"
upload_value SSH_PUBLIC_KEY       "$ssh_public_key"

# ── Telemetry S3 credentials ─────────────────────────────────────────────────

echo ""
echo "── Telemetry S3 credentials (OCI Customer Secret Keys) ──────────────────"
echo "  Used by Loki, Tempo, and VictoriaMetrics (vmbackup/vmrestore)."
echo "  OCI Console → Profile → User Settings → Customer Secret Keys → Generate Secret Key."
echo ""
if grep -q '^#' "$SECRETS_DIR/telemetry_s3_access_key" 2>/dev/null; then
  echo "  SKIP TELEMETRY_S3_ACCESS_KEY — placeholder not yet filled in"
  echo "       Edit secrets/telemetry_s3_access_key with the Customer Secret Key access key."
else
  upload_file TELEMETRY_S3_ACCESS_KEY "$SECRETS_DIR/telemetry_s3_access_key"
  upload_file TELEMETRY_S3_SECRET_KEY "$SECRETS_DIR/telemetry_s3_secret_key"
fi

# ── Terraform state backend ───────────────────────────────────────────────────

echo ""
echo "── Terraform state backend (OCI Object Storage S3) ──────────────────────"
echo "  Setup steps (if not done already):"
echo "    1. OCI Console → Object Storage → Buckets → Create Bucket"
echo "       Name: terraform-state  |  Region: ap-sydney-1  |  Visibility: Private"
echo "    2. Get namespace: shown in the Object Storage page header"
echo "    3. Profile → User Settings → Customer Secret Keys → Generate Secret Key"
echo "       Copy the secret value immediately — it won't be shown again."
echo ""
prompt tf_state_namespace  "OCI namespace        (shown in Object Storage page header)"
prompt tf_state_access_key "TF_STATE_ACCESS_KEY  (Customer Secret Key — Access Key field)"
prompt tf_state_secret_key "TF_STATE_SECRET_KEY  (Customer Secret Key — Secret value)" silent

tf_state_endpoint="https://${tf_state_namespace}.compat.objectstorage.ap-sydney-1.oraclecloud.com"
echo "  Endpoint: $tf_state_endpoint"

upload_value TF_STATE_ENDPOINT   "$tf_state_endpoint"
upload_value TF_STATE_ACCESS_KEY "$tf_state_access_key"
upload_value TF_STATE_SECRET_KEY "$tf_state_secret_key"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "── Done ──────────────────────────────────────────────────────────────────"
echo "  All secrets uploaded."
echo ""
echo "  Next steps:"
echo "    1. Fill in secrets/wireguard_mikrotik_public.key (once MikroTik is configured)"
echo "       then re-run this script to upload WG_MIKROTIK_PUBLIC_KEY."
echo "    2. Go to GitHub → Actions → Deploy Infrastructure → Run workflow"
echo "       Choose 'plan' first to validate, then 'apply' to provision."
echo ""
echo "  Gateway WireGuard public key (for MikroTik peer config):"
cat "$SECRETS_DIR/wireguard_gateway_public.key"
