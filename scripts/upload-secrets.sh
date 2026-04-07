#!/usr/bin/env bash
# Uploads all required GitHub Actions secrets for this repository and homelab-deploy.
#
# Requirements:
#   gh CLI installed and authenticated (run: gh auth login)
#   linode-cli authenticated (run: make linode-login)
#   uv installed with scripts/ venv synced (run: make setup)
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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

linode_token_create() {
  local label="$1"
  local scopes="$2"
  local expiry
  expiry=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%M:%S')
  local token
  token=$(uv run --directory "$SCRIPT_DIR" linode-cli profile token-create \
      --label "$label" \
      --scopes "$scopes" \
      --expiry "$expiry" \
      --json 2>/dev/null \
    | python3 -c "import sys,json; print(json.loads(sys.stdin.read())[0]['token'])")
  printf '%s' "$token"
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
# Uses the authenticated linode-cli session to generate two scoped tokens:
#   LINODE_PACKER_TOKEN — used by packer-build to mint short-lived build tokens
#   LINODE_TF_TOKEN     — used by terraform-plan/apply to mint short-lived infra tokens
# Both tokens include account:read_write so they can mint and revoke child tokens.
# Both expire after 2 hours — re-run this script to rotate them.

echo ""
echo "── Linode API ────────────────────────────────────────────────────────────"
echo "  Generating scoped tokens via authenticated linode-cli session..."
echo "  (run 'make linode-login' first if not already authenticated)"
echo ""
echo "  Generating LINODE_PACKER_TOKEN..."
linode_packer_token=$(linode_token_create \
  "homelab-packer" \
  "account:read_write linodes:read_write images:read_write events:read_only")
upload_to "$DEPLOY_REPO" LINODE_PACKER_TOKEN "$linode_packer_token"

echo "  Generating LINODE_TF_TOKEN..."
linode_tf_token=$(linode_token_create \
  "homelab-terraform" \
  "account:read_write linodes:read_write firewall:read_write events:read_only images:read_only object_storage:read_write")
upload_to "$DEPLOY_REPO" LINODE_TF_TOKEN "$linode_tf_token"

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
echo "    2. Create the Terraform state bucket: make tf-init-bucket"
echo "    3. Push to main — CI will build the image and deploy automatically."
echo ""
echo "  Note: LINODE_PACKER_TOKEN and LINODE_TF_TOKEN expire in 2 hours."
echo "  Re-run this script to rotate them before the next CI run."
echo ""
