#!/usr/bin/env bash
set -euo pipefail

ROOT="/piscessmp"
SERVER_DIR="$ROOT/server"
DEPLOY_DIR="$ROOT/deploy"

cd "$ROOT"

if [[ ! -f "$SERVER_DIR/paper.jar" ]]; then
  echo "First run — downloading Paper and plugins..."
  bash "$ROOT/scripts/debian-setup.sh"
fi

if [[ "${ACCEPT_EULA:-false}" == "true" ]]; then
  echo 'eula=true' > "$SERVER_DIR/eula.txt"
elif [[ ! -f "$SERVER_DIR/eula.txt" ]] || ! grep -q '^eula=true' "$SERVER_DIR/eula.txt"; then
  echo "Set ACCEPT_EULA=true to accept https://aka.ms/MinecraftEULA"
  exit 1
fi

if [[ -n "${RCON_PASSWORD:-}" ]]; then
  cat > "$DEPLOY_DIR/backup.env" <<EOF
RCON_PASSWORD=${RCON_PASSWORD}
RCON_HOST=127.0.0.1
RCON_PORT=${RCON_PORT:-25575}
BACKUP_RETAIN=${BACKUP_RETAIN:-7}
EOF
fi

if [[ ! -f "$SERVER_DIR/server-icon.png" ]] && [[ -f "$ROOT/docker/server-icon.png" ]]; then
  cp "$ROOT/docker/server-icon.png" "$SERVER_DIR/server-icon.png"
fi

if [[ ! -f "$SERVER_DIR/.docker-prepared" ]]; then
  bash "$ROOT/scripts/configure.sh" --prepare || true
  touch "$SERVER_DIR/.docker-prepared"
fi

export MEMORY_MIN="${MEMORY_MIN:-2G}"
export MEMORY_MAX="${MEMORY_MAX:-4G}"
export UPDATE_ON_START="${UPDATE_ON_START:-false}"

exec bash "$ROOT/scripts/start.sh"
