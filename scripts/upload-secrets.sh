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

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "── Done ──────────────────────────────────────────────────────────────────"
echo "  All secrets uploaded."
echo ""
echo "  Next steps:"
echo "    1. Create the Terraform state bucket (one-time):  make tf-init-bucket"
echo "    2. Push to main — CI will build the image and deploy automatically."
echo "    3. Or deploy locally:  make tf-init && make tf-plan && make tf-deploy"
echo ""
