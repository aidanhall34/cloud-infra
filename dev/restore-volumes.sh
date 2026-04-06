#!/usr/bin/env bash
# restore-volumes.sh — restore dev LGTM telemetry volumes from S3.
#
# Usage:
#   ./restore-volumes.sh               # restore the latest backup
#   ./restore-volumes.sh <filename>    # restore a specific backup by exact filename
#
# Reads S3 credentials from secrets/dev-backup.env.
# The dev stack is stopped and all three volumes are PERMANENTLY OVERWRITTEN.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_FILE="${SCRIPT_DIR}/../secrets/dev-backup.env"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

die() { echo -e "${RED}error:${RESET} $*" >&2; exit 1; }

# ── Dependency check ──────────────────────────────────────────────────────────
command -v aws  >/dev/null 2>&1 || die "aws CLI not found — install it first"
command -v docker >/dev/null 2>&1 || die "docker not found"

# ── Load secrets ──────────────────────────────────────────────────────────────
[[ -f "$SECRETS_FILE" ]] || die "$SECRETS_FILE not found — run: make dev-backup-secrets"

set -a
# shellcheck disable=SC1090
source <(grep -Ev '^[[:space:]]*#|^[[:space:]]*$' "$SECRETS_FILE")
set +a

: "${AWS_S3_BUCKET_NAME:?AWS_S3_BUCKET_NAME must be set in $SECRETS_FILE}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID must be set in $SECRETS_FILE}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY must be set in $SECRETS_FILE}"

# ── Build AWS CLI args ────────────────────────────────────────────────────────
AWS_ARGS=(--region "${AWS_REGION:-auto}")
if [[ -n "${AWS_ENDPOINT:-}" ]]; then
  # Normalise: AWS CLI requires a full URL with scheme.
  ENDPOINT="${AWS_ENDPOINT}"
  [[ "$ENDPOINT" != http://* && "$ENDPOINT" != https://* ]] && ENDPOINT="https://${ENDPOINT}"
  AWS_ARGS+=(--endpoint-url "$ENDPOINT")
fi

# Strip any trailing slash from the path before building the prefix.
S3_PATH="${AWS_S3_PATH%/}"
S3_PREFIX="s3://${AWS_S3_BUCKET_NAME}${S3_PATH:+/$S3_PATH}"

# ── Select backup ─────────────────────────────────────────────────────────────
TARGET_FILE="${1:-}"

if [[ -z "$TARGET_FILE" ]]; then
  echo "Listing backups at ${S3_PREFIX} ..."
  LISTING=$(aws s3 ls "${AWS_ARGS[@]}" "${S3_PREFIX}/" 2>/dev/null \
    | grep -E 'homelab-[0-9]{8}-[0-9]{6}' \
    | sort) || true
  [[ -n "$LISTING" ]] || die "no backups found at ${S3_PREFIX}"

  LATEST_LINE=$(tail -1 <<< "$LISTING")
  TARGET_FILE=$(awk '{print $NF}' <<< "$LATEST_LINE")
  FILE_BYTES=$(awk '{print $3}' <<< "$LATEST_LINE")
  FILE_DATE=$(awk '{print $1" "$2}' <<< "$LATEST_LINE")
else
  META=$(aws s3 ls "${AWS_ARGS[@]}" "${S3_PREFIX}/${TARGET_FILE}" 2>/dev/null) \
    || die "backup not found: ${S3_PREFIX}/${TARGET_FILE}"
  FILE_BYTES=$(awk '{print $3}' <<< "$META")
  FILE_DATE=$(awk '{print $1" "$2}' <<< "$META")
fi

# ── Format file size ──────────────────────────────────────────────────────────
FORMATTED_SIZE=$(awk -v b="$FILE_BYTES" 'BEGIN {
  if      (b >= 1073741824) printf "%.2f GiB", b / 1073741824
  else if (b >= 1048576)    printf "%.2f MiB", b / 1048576
  else if (b >= 1024)       printf "%.2f KiB", b / 1024
  else                      printf "%d bytes", b
}')

# ── Warning ───────────────────────────────────────────────────────────────────
echo
echo -e "${RED}${BOLD}WARNING: DESTRUCTIVE OPERATION${RESET}"
echo -e "${YELLOW}The following Docker volumes will be stopped, wiped, and overwritten:${RESET}"
echo -e "  ${CYAN}dev-prometheus-data${RESET}  —  Prometheus TSDB blocks + WAL"
echo -e "  ${CYAN}dev-loki-data${RESET}         —  Loki chunks + WAL"
echo -e "  ${CYAN}dev-tempo-data${RESET}        —  Tempo blocks + WAL"
echo
echo -e "${BOLD}Backup to restore:${RESET}"
echo -e "  File:      ${CYAN}${TARGET_FILE}${RESET}"
echo -e "  Location:  ${S3_PREFIX}/${TARGET_FILE}"
echo -e "  Timestamp: ${FILE_DATE} UTC"
echo -e "  Size:      ${FORMATTED_SIZE}"
echo
printf "${RED}${BOLD}Type 'yes' to confirm restoration (local data will be lost): ${RESET}"
read -r CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 1; }

# ── Download ──────────────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

ARCHIVE="${WORK_DIR}/${TARGET_FILE}"
echo
echo "Downloading ${TARGET_FILE} ..."
aws s3 cp "${AWS_ARGS[@]}" "${S3_PREFIX}/${TARGET_FILE}" "$ARCHIVE"

# ── Decrypt ───────────────────────────────────────────────────────────────────
if [[ "$ARCHIVE" == *.gpg ]]; then
  [[ -n "${GPG_PASSPHRASE:-}" ]] \
    || die "archive is GPG-encrypted but GPG_PASSPHRASE is not set"
  command -v gpg >/dev/null 2>&1 || die "gpg not found — required to decrypt backup"

  echo "Decrypting archive ..."
  DECRYPTED="${ARCHIVE%.gpg}"
  gpg --batch --yes --passphrase "$GPG_PASSPHRASE" \
    --output "$DECRYPTED" --decrypt "$ARCHIVE"
  rm "$ARCHIVE"
  ARCHIVE="$DECRYPTED"
fi

# ── Stop the stack ────────────────────────────────────────────────────────────
echo "Stopping dev stack ..."
docker compose -f "$COMPOSE_FILE" down

# ── Restore each volume ───────────────────────────────────────────────────────
# The backup archive layout mirrors the docker-compose volume mounts:
#   backup/prometheus/ → dev-prometheus-data
#   backup/loki/       → dev-loki-data
#   backup/tempo/      → dev-tempo-data
# --strip-components=2 removes the "backup/<name>" prefix so content lands
# directly at the volume root.
restore_volume() {
  local volume="$1"
  local tar_path="$2"   # path prefix inside the archive

  echo "Restoring ${volume} ..."
  docker run --rm \
    -v "${volume}:/target" \
    -v "${ARCHIVE}:/archive.tar.gz:ro" \
    alpine sh -c "
      rm -rf /target/* /target/.[!.]* 2>/dev/null || true
      tar -xzf /archive.tar.gz --strip-components=2 -C /target '${tar_path}'
    "
}

restore_volume "dev-prometheus-data" "backup/prometheus"
restore_volume "dev-loki-data"       "backup/loki"
restore_volume "dev-tempo-data"      "backup/tempo"

echo
echo -e "${CYAN}${BOLD}Restoration complete.${RESET}"
echo "Start the stack with:  make dev-up"
