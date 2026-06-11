#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$ROOT/server"
DEPLOY_DIR="$ROOT/deploy"
TEMPLATES="$SERVER_DIR/config-templates"
PREPARE=false
APPLY=false
RCON=false

usage() {
  cat <<'EOF'
Usage: ./scripts/configure.sh [--prepare|--apply|--rcon]

  --prepare   Write config templates before first start
  --apply     Apply templates after first start (Geyser, TAB, server.properties)
  --rcon      Generate RCON password + backup.env
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare) PREPARE=true ;;
    --apply) APPLY=true ;;
    --rcon) RCON=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

if ! $PREPARE && ! $APPLY && ! $RCON; then
  usage
  exit 1
fi

mkdir -p "$TEMPLATES"

if $PREPARE; then
  cat > "$TEMPLATES/server.properties.recommended" <<'EOF'
# Append or merge these after first server start
motd=Pisces SMP
max-players=20
online-mode=true
enable-rcon=true
rcon.port=25575
spawn-protection=16
view-distance=10
simulation-distance=10
EOF

  cat > "$TEMPLATES/geyser-config.patch" <<'EOF'
# plugins/Geyser-Spigot/config.yml — set after first start:
#   bedrock.port: 19132
#   remote.auth-type: floodgate
EOF

  cat > "$TEMPLATES/bluemap-config-notes.txt" <<'EOF'
# After first start, BlueMap config lives in plugins/BlueMap/storages/config/
# Default web map: http://your-ip:8100
# In-game: /bluemap help
# With Caddy: https://map.yourdomain.com (see deploy/domain.env.example)
EOF

  cat > "$TEMPLATES/luckperms-commands.txt" <<'EOF'
/lp creategroup default
/lp creategroup member
/lp creategroup staff
/lp creategroup admin
/lp group default meta setprefix "&7"
/lp group member meta setprefix "&a[Member] &r"
/lp group staff meta setprefix "&b[Staff] &r"
/lp group admin meta setprefix "&c[Admin] &r"
/lp group member parent add default
/lp group staff parent add member
/lp group admin parent add staff
/lp group staff permission set staff.* true
EOF
fi

if $RCON; then
  PASS="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
  cat > "$DEPLOY_DIR/backup.env" <<EOF
RCON_PASSWORD=$PASS
RCON_HOST=127.0.0.1
RCON_PORT=25575
BACKUP_RETAIN=7
EOF
  chmod 600 "$DEPLOY_DIR/backup.env"
  echo "Created deploy/backup.env with generated RCON password"
  echo "After first start, set the same password in server/server.properties"
fi

if $APPLY; then
  # TAB groups
  if [[ -f "$TEMPLATES/TAB-groups.yml" ]]; then
    mkdir -p "$SERVER_DIR/plugins/TAB"
    cp "$TEMPLATES/TAB-groups.yml" "$SERVER_DIR/plugins/TAB/groups.yml"
    echo "Applied TAB groups.yml"
  fi

  # Geyser config
  GEYSER_CONFIG="$SERVER_DIR/plugins/Geyser-Spigot/config.yml"
  if [[ -f "$GEYSER_CONFIG" ]]; then
    python3 - "$GEYSER_CONFIG" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
replacements = {
    "  auth-type: online": "  auth-type: floodgate",
    "  auth-type: offline": "  auth-type: floodgate",
}
for old, new in replacements.items():
    if old in text:
        text = text.replace(old, new)
if "auth-type: floodgate" not in text and "remote:" in text:
    text = text.replace("remote:", "remote:\n  auth-type: floodgate", 1)
path.write_text(text)
print("Patched Geyser auth-type → floodgate")
PY
  else
    echo "Geyser config not found — start server once first"
  fi

  # server.properties — merge RCON + recommended keys
  PROPS="$SERVER_DIR/server.properties"
  REC="$TEMPLATES/server.properties.recommended"
  if [[ -f "$PROPS" ]] && [[ -f "$REC" ]]; then
    python3 - "$PROPS" "$REC" "$DEPLOY_DIR/backup.env" <<'PY'
import sys
from pathlib import Path

props_path, rec_path, backup_env = sys.argv[1:4]
props = {}
for line in Path(props_path).read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    props[key] = value

for line in Path(rec_path).read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    props.setdefault(key, value)

if Path(backup_env).is_file():
    for line in Path(backup_env).read_text().splitlines():
        if line.startswith("RCON_PASSWORD="):
            props["rcon.password"] = line.split("=", 1)[1]
            props["enable-rcon"] = "true"
            props["rcon.port"] = props.get("rcon.port", "25575")
            break

lines = [f"{k}={v}" for k, v in props.items()]
Path(props_path).write_text("\n".join(lines) + "\n")
print("Merged server.properties recommendations + RCON")
PY
  fi

  # SimpleVoice-Geyser
  SVG_CONFIG="$SERVER_DIR/plugins/SimpleVoice-Geyser/config.yml"
  if [[ -f "$SVG_CONFIG" ]]; then
    if ! grep -q 'requireBedrock: false' "$SVG_CONFIG" 2>/dev/null; then
      sed -i.bak 's/requireBedrock: true/requireBedrock: false/' "$SVG_CONFIG" 2>/dev/null || \
        echo "Set requireBedrock: false in SimpleVoice-Geyser config manually"
    fi
    echo "Checked SimpleVoice-Geyser config"
  fi

  # DiscordSRV — copy example config if missing
  DSRV_CONFIG="$SERVER_DIR/plugins/DiscordSRV/config.yml"
  if [[ -f "$TEMPLATES/discordsrv-config.yml.example" ]] && [[ ! -f "$DSRV_CONFIG" ]]; then
    mkdir -p "$SERVER_DIR/plugins/DiscordSRV"
    cp "$TEMPLATES/discordsrv-config.yml.example" "$DSRV_CONFIG"
    echo "Created DiscordSRV config — add your bot token and channel ID"
  fi

  # Domain hint in server.properties
  DOMAIN_ENV="$DEPLOY_DIR/domain.env"
  if [[ -f "$PROPS" ]] && [[ -f "$DOMAIN_ENV" ]]; then
    # shellcheck source=/dev/null
    source "$DOMAIN_ENV"
    if [[ -n "${DOMAIN:-}" ]] && [[ "$DOMAIN" != *"example.com"* ]]; then
      if ! grep -q "^server-name=" "$PROPS" 2>/dev/null; then
        echo "server-name=$DOMAIN" >> "$PROPS"
        echo "Set server-name → $DOMAIN"
      fi
    fi
  fi

  echo "Configuration applied — restart the server."
fi
