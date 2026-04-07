#!/usr/bin/env bash
# Uploads all required GitHub Actions secrets for this repository.
#
# Requirements:
#   gh CLI installed and authenticated (run: gh auth login)
#
# Usage:
#   ./scripts/upload-secrets.sh                  # uses current repo
#   ./scripts/upload-secrets.sh owner/repo-name  # explicit repo

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
    read -rp "  $label: " "$var_name"
  fi
}

# ── Discord ───────────────────────────────────────────────────────────────────

echo ""
echo "── Discord ───────────────────────────────────────────────────────────────"
echo "  Create a webhook at: Server Settings → Integrations → Webhooks"
echo ""
prompt discord_webhook_url "DISCORD_WEBHOOK_URL"
upload_value DISCORD_WEBHOOK_URL "$discord_webhook_url"

# ── Linode API ────────────────────────────────────────────────────────────────

echo ""
echo "── Linode API ────────────────────────────────────────────────────────────"
echo "  Create a token with full access at: https://cloud.linode.com/profile/tokens"
echo "  Or scope it minimally: linodes:read_write images:read_write firewall:read_write"
echo ""
prompt linode_token "LINODE_TOKEN" silent
upload_value LINODE_TOKEN "$linode_token"

# ── Terraform — gateway ───────────────────────────────────────────────────────

echo ""
echo "── Terraform — gateway ───────────────────────────────────────────────────"
echo ""
prompt ssh_public_key   "TF_SSH_PUBLIC_KEY   (contents of ~/.ssh/id_ed25519.pub)"
prompt allowed_ip_range "TF_ALLOWED_IP_RANGE (your home CIDR, e.g. 203.0.113.1/32)"

upload_value TF_SSH_PUBLIC_KEY   "$ssh_public_key"
upload_value TF_ALLOWED_IP_RANGE "$allowed_ip_range"

# ── Terraform state backend (Linode Object Storage) ───────────────────────────

echo ""
echo "── Terraform state backend (Linode Object Storage) ──────────────────────"
echo "  Setup steps (if not done already):"
echo "    1. Create a bucket: https://cloud.linode.com/object-storage/buckets"
echo "    2. Generate access keys: https://cloud.linode.com/object-storage/access-keys"
echo ""
echo "  Cluster IDs by region:"
echo "    ap-southeast  → ap-southeast-1"
echo "    us-east       → us-east-1"
echo "    eu-central    → eu-central-1"
echo ""
prompt tf_state_bucket     "TF_STATE_BUCKET     (bucket name)"
prompt tf_state_region     "TF_STATE_REGION     (cluster ID, e.g. ap-southeast-1)"
prompt tf_state_endpoint   "TF_STATE_ENDPOINT   (e.g. ap-southeast-1.linodeobjects.com)"
prompt tf_state_access_key "TF_STATE_ACCESS_KEY (access key)"
prompt tf_state_secret_key "TF_STATE_SECRET_KEY (secret key)" silent

upload_value TF_STATE_BUCKET     "$tf_state_bucket"
upload_value TF_STATE_REGION     "$tf_state_region"
upload_value TF_STATE_ENDPOINT   "$tf_state_endpoint"
upload_value TF_STATE_ACCESS_KEY "$tf_state_access_key"
upload_value TF_STATE_SECRET_KEY "$tf_state_secret_key"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "── Done ──────────────────────────────────────────────────────────────────"
echo "  All secrets uploaded."
echo ""
echo "  Next steps:"
echo "    1. Build the gateway image:  make linode-packer-token && make packer-build-gateway"
echo "    2. Deploy infrastructure:    make linode-deploy-token && make tf-init tf-plan tf-apply"
echo "    3. Or push to main and let CI do it automatically."
echo ""
