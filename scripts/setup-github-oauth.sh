#!/usr/bin/env bash
# Creates a GitHub OAuth App for Grafana SSO and saves credentials to secrets/.
#
# Prerequisites:
#   - gh CLI installed and authenticated (`gh auth login`)
#   - gh auth token must have `admin:org` scope (for org-level apps) or
#     be a personal access token with `write:applications` scope.
#     Re-auth with extra scopes: gh auth login --scopes admin:org
#
# Usage:
#   scripts/setup-github-oauth.sh [--org <org>] [--grafana-url <url>]
#
# Defaults:
#   --org          personal account (no org)
#   --grafana-url  http://localhost:3000 (override after you know the VM IP)
#
# After running, upload the generated secrets to GitHub:
#   make upload-secrets

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="$REPO_ROOT/secrets"

APP_NAME="Homelab Grafana"
ORG=""
GRAFANA_URL="http://localhost:3000"

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)          ORG="$2";         shift 2 ;;
    --grafana-url)  GRAFANA_URL="$2"; shift 2 ;;
    *)              echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

CALLBACK_URL="${GRAFANA_URL}/login/github"

echo "==> Creating GitHub OAuth App: \"$APP_NAME\""
echo "    Callback URL : $CALLBACK_URL"
if [ -n "$ORG" ]; then
  echo "    Organisation : $ORG"
else
  echo "    Scope        : personal account"
fi
echo ""

# ── Create the OAuth App ──────────────────────────────────────────────────────
# GitHub's REST API for OAuth Apps requires specific scopes not exposed via the
# standard gh CLI shorthand. We use `gh api` with explicit JSON fields.

if [ -n "$ORG" ]; then
  ENDPOINT="/orgs/${ORG}/oauthapps"
else
  # Personal OAuth Apps live under /user; the gh CLI authenticates as the
  # current user automatically.
  ENDPOINT="/user/applications"
fi

response=$(gh api \
  --method POST \
  "$ENDPOINT" \
  -f name="$APP_NAME" \
  -f url="${GRAFANA_URL}" \
  -f callback_url="$CALLBACK_URL" \
  2>&1) || {
    echo ""
    echo "ERROR: gh api call failed. This usually means one of:"
    echo "  1. Your gh token lacks the required scope."
    echo "     Fix: gh auth login --scopes admin:org"
    echo "  2. The GitHub API endpoint differs for your account type."
    echo ""
    echo "Manual steps:"
    echo "  1. Go to: https://github.com/settings/developers"
    echo "     (or https://github.com/organizations/${ORG:-YOUR_ORG}/settings/applications)"
    echo "  2. Click 'New OAuth App'"
    echo "  3. Fill in:"
    echo "     Application name : $APP_NAME"
    echo "     Homepage URL     : $GRAFANA_URL"
    echo "     Callback URL     : $CALLBACK_URL"
    echo "  4. Generate a client secret and save both values:"
    echo "     echo '<client_id>'     > $SECRETS_DIR/grafana_github_client_id"
    echo "     echo '<client_secret>' > $SECRETS_DIR/grafana_github_client_secret"
    exit 1
  }

client_id=$(echo "$response"     | python3 -c "import sys,json; print(json.load(sys.stdin)['client_id'])")
client_secret=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['client_secret'])")

# ── Save credentials ──────────────────────────────────────────────────────────
mkdir -p "$SECRETS_DIR"
printf '%s\n' "$client_id"     > "$SECRETS_DIR/grafana_github_client_id"
printf '%s\n' "$client_secret" > "$SECRETS_DIR/grafana_github_client_secret"
chmod 600 \
  "$SECRETS_DIR/grafana_github_client_id" \
  "$SECRETS_DIR/grafana_github_client_secret"

echo "==> Credentials saved:"
echo "    $SECRETS_DIR/grafana_github_client_id"
echo "    $SECRETS_DIR/grafana_github_client_secret"
echo ""
echo "Next steps:"
echo "  1. Update terraform.tfvars (or CI vars) with:"
echo "       grafana_github_org   = \"${ORG:-<your-org-or-username>}\""
echo "       grafana_admin_user   = \"<your-github-username>\""
echo "  2. Upload secrets to GitHub: make upload-secrets"
echo "  3. Re-run terraform apply so the new grafana.ini is baked into cloud-init."
