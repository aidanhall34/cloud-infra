#!/usr/bin/env bash
# Uploads all required GitHub Actions secrets for this repository and homelab-deploy.
#
# Requirements:
#   gh CLI installed and authenticated (run: gh auth login)
#   Both aidanhall34/cloud-infra and aidanhall34/homelab-deploy must be accessible.
#
# Usage:
#   ./scripts/upload-secrets.sh
#
# Note: GitHub App credentials (APP_ID, APP_PRIVATE_KEY) are managed separately.
#   Run: make configure-github-app

set -euo pipefail

CLOUD_INFRA_REPO="aidanhall34/cloud-infra"
DEPLOY_REPO="aidanhall34/homelab-deploy"

# ── Helpers ───────────────────────────────────────────────────────────────────

upload_to() {
  local repo="$1"
  local name="$2"
  local value="$3"
  printf '%s' "$value" | gh secret set "$name" --repo "$repo"
  echo "  OK   $name → $repo"
}

upload_to_both() {
  local name="$1"
  local value="$2"
  upload_to "$CLOUD_INFRA_REPO" "$name" "$value"
  upload_to "$DEPLOY_REPO"      "$name" "$value"
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
# Uploaded to both repos — cloud-infra uses it for molecule notifications,
# homelab-deploy uses it for packer/terraform notifications.

echo ""
echo "── Discord ───────────────────────────────────────────────────────────────"
echo "  Create a webhook at: Server Settings → Integrations → Webhooks"
echo ""
prompt discord_webhook_url "DISCORD_WEBHOOK_URL"
upload_to_both DISCORD_WEBHOOK_URL "$discord_webhook_url"

# ── Linode API ────────────────────────────────────────────────────────────────
# homelab-deploy only — cloud-infra no longer runs builds directly.

echo ""
echo "── Linode API ────────────────────────────────────────────────────────────"
echo "  Create a token with full access at: https://cloud.linode.com/profile/tokens"
echo "  Or scope it minimally: linodes:read_write images:read_write firewall:read_write"
echo ""
prompt linode_token "LINODE_TOKEN" silent
upload_to "$DEPLOY_REPO" LINODE_TOKEN "$linode_token"

# ── Terraform — gateway ───────────────────────────────────────────────────────
# homelab-deploy only.

echo ""
echo "── Terraform — gateway ───────────────────────────────────────────────────"
echo ""
prompt ssh_public_key   "TF_SSH_PUBLIC_KEY   (contents of ~/.ssh/id_ed25519.pub)"
prompt allowed_ip_range "TF_ALLOWED_IP_RANGE (your home CIDR, e.g. 203.0.113.1/32)"

upload_to "$DEPLOY_REPO" TF_SSH_PUBLIC_KEY   "$ssh_public_key"
upload_to "$DEPLOY_REPO" TF_ALLOWED_IP_RANGE "$allowed_ip_range"

# ── OTEL ──────────────────────────────────────────────────────────────────────
# homelab-deploy only — traces are emitted by packer/terraform builds.

echo ""
echo "── OTEL ──────────────────────────────────────────────────────────────────"
echo "  gRPC endpoint for OpenTelemetry traces (e.g. https://tempo.example.com:4317)"
echo ""
prompt otel_endpoint "OTEL_ENDPOINT"
upload_to "$DEPLOY_REPO" OTEL_ENDPOINT "$otel_endpoint"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "── Done ──────────────────────────────────────────────────────────────────"
echo "  All secrets uploaded."
echo ""
echo "  Next steps:"
echo "    1. Configure GitHub App credentials:  make configure-github-app"
echo "    2. Configure deploy environment:      make configure-deploy-environment"
echo "    3. Create the Terraform state bucket: make tf-init-bucket"
echo "    4. Push to main — CI will build the image and deploy automatically."
echo ""
