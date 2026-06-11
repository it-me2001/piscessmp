#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESTART=false
CHECK=false
FORCE=false

usage() {
  cat <<'EOF'
Usage: ./scripts/update.sh [options]

Options:
  --check       Show available updates without downloading
  --force       Re-download all components even if up to date
  --restart     Restart systemd service after updating (requires piscessmp.service)
  -h, --help    Show this help

Examples:
  ./scripts/update.sh --check
  ./scripts/update.sh
  ./scripts/update.sh --restart
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=true ;;
    --force) FORCE=true ;;
    --restart) RESTART=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

for cmd in python3 unzip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    exit 1
  fi
done

ARGS=(--root "$ROOT")
if $CHECK; then ARGS+=(--check); fi
if $FORCE; then ARGS+=(--force); fi

set +e
python3 "$ROOT/scripts/update-lib.py" "${ARGS[@]}"
STATUS=$?
set -e

if [[ "${BACKUP_BEFORE_UPDATE:-true}" == "true" ]] && [[ $STATUS -eq 10 ]]; then
  echo "Creating pre-update backup..."
  bash "$ROOT/scripts/backup.sh" || true
fi

if [[ $STATUS -eq 10 ]] && $RESTART && command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet piscessmp 2>/dev/null; then
    echo "Restarting piscessmp service..."
    sudo systemctl restart piscessmp
  else
    echo "piscessmp service is not running — start manually with ./scripts/start.sh"
  fi
fi

if [[ $STATUS -eq 10 ]]; then
  exit 0
fi

exit "$STATUS"
