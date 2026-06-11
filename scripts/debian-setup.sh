#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$ROOT/server"
PLUGINS_DIR="$SERVER_DIR/plugins"

echo "Pisces SMP — Debian setup"
echo "Project root: $ROOT"
echo

for cmd in bash curl python3 unzip java; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing dependency: $cmd"
    echo "Install with: sudo ./scripts/debian-install-deps.sh"
    exit 1
  fi
done

JAVA_MAJOR="$({ java -version 2>&1 || true; } | awk -F '[\".]' '/version/ {print $2; exit}')"
if [[ "${JAVA_MAJOR:-0}" -lt 21 ]]; then
  echo "Java 21+ required for Paper 1.21.x (found Java ${JAVA_MAJOR:-unknown})"
  echo "Install with: sudo ./scripts/debian-install-deps.sh"
  exit 1
fi

mkdir -p "$PLUGINS_DIR" "$SERVER_DIR/config-templates"

echo "→ Downloading Paper 1.21.11"
bash "$ROOT/scripts/download-paper.sh"

echo "→ Downloading plugins"
bash "$ROOT/scripts/download-plugins.sh"

if [[ ! -f "$SERVER_DIR/eula.txt" ]]; then
  cat > "$SERVER_DIR/eula.txt" <<'EOF'
# Change to eula=true after reading https://aka.ms/MinecraftEULA
eula=false
EOF
  echo "Created server/eula.txt — set eula=true before first start"
fi

if [[ -f "$ROOT/server/config-templates/TAB-groups.yml" ]] && [[ ! -f "$SERVER_DIR/plugins/TAB/groups.yml" ]]; then
  echo "TAB config: copy server/config-templates/TAB-groups.yml to server/plugins/TAB/groups.yml after first start"
fi

chmod +x "$ROOT/scripts/"*.sh "$ROOT/scripts/update-lib.py"

if [[ ! -f "$ROOT/deploy/backup.env" ]] && [[ -f "$ROOT/deploy/backup.env.example" ]]; then
  echo "Optional: cp deploy/backup.env.example deploy/backup.env and set RCON_PASSWORD"
fi

echo
echo "Debian setup complete."
echo
echo "Next steps:"
echo "  Run the full installer: ./setup.sh --production --accept-eula"
echo "  Or manually:"
echo "    1. echo 'eula=true' > $SERVER_DIR/eula.txt"
echo "    2. ./scripts/start.sh"
echo "    3. ./scripts/configure.sh --apply"
