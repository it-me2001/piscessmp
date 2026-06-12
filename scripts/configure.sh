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
motd=\u00a7f\u00a7lPISCES\u00a7r\n\u00a7bSMP
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
/lp group default permission set essentials.home true
/lp group default permission set essentials.sethome true
/lp group default permission set essentials.delhome true
/lp group default permission set essentials.sethome.multiple true
/lp group default permission set essentials.sethome.multiple.3 true
/lp group default permission set essentials.tpa true
/lp group default permission set essentials.tpaccept true
/lp group default permission set essentials.tpdeny true
/lp group default permission set essentials.spawn true
/lp group default permission set betterrtp.use true
/lp group member permission set essentials.sethome.multiple.5 true
/lp group staff permission set essentials.sethome.multiple.10 true
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

  # BetterRTP — survival-friendly cooldown + radius (after first start)
  BETTERRTP_CONFIG="$SERVER_DIR/plugins/BetterRTP/config.yml"
  if [[ -f "$BETTERRTP_CONFIG" ]]; then
    python3 - "$BETTERRTP_CONFIG" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text().splitlines()
in_delay = in_cooldown = False
out = []
for line in lines:
    stripped = line.strip()
    if stripped.startswith("Delay:"):
        in_delay, in_cooldown = True, False
    elif stripped.startswith("Cooldown:"):
        in_delay, in_cooldown = False, True
    elif stripped and not line.startswith(" ") and stripped.endswith(":"):
        in_delay = in_cooldown = False
    if in_delay and stripped.startswith("Time:"):
        indent = line[: len(line) - len(line.lstrip())]
        line = f"{indent}Time: 5"
    if in_delay and stripped.startswith("Enabled:"):
        indent = line[: len(line) - len(line.lstrip())]
        line = f"{indent}Enabled: true"
    if in_cooldown and stripped.startswith("Time:"):
        indent = line[: len(line) - len(line.lstrip())]
        line = f"{indent}Time: 300"
    if in_cooldown and stripped.startswith("Enabled:"):
        indent = line[: len(line) - len(line.lstrip())]
        line = f"{indent}Enabled: true"
    out.append(line)

path.write_text("\n".join(out) + "\n")
print("Patched BetterRTP delay (5s) + cooldown (300s)")
PY
  else
    echo "BetterRTP config not found — start server once after installing BetterRTP.jar"
  fi

  # EssentialsX — named homes + hub spawn (/spawn, spawn-on-join)
  ESSENTIALS_CONFIG="$SERVER_DIR/plugins/Essentials/config.yml"
  if [[ -f "$ESSENTIALS_CONFIG" ]]; then
    if ! grep -q "allow-user-home-names:" "$ESSENTIALS_CONFIG" 2>/dev/null; then
      echo "allow-user-home-names: true" >> "$ESSENTIALS_CONFIG"
      echo "Enabled EssentialsX named homes (allow-user-home-names)"
    fi
    python3 - "$ESSENTIALS_CONFIG" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
text = re.sub(r"(?m)^(\s*)-\s*spawn\s*$", "", text)
text = re.sub(r"spawn-on-join:\s*false", "spawn-on-join: true", text)
spawn_block = """spawns:
  default:
    world: spawn
    x: 0.5
    y: 65.0
    z: 0.5
    yaw: 0.0
    pitch: 0.0
"""
if "spawns:" in text:
    text = re.sub(
        r"spawns:\s*\n\s*default:\s*\n(?:\s+\w+:.*\n)+",
        spawn_block,
        text,
        count=1,
    )
else:
    text = text.rstrip() + "\n\nspawn-on-join: true\n" + spawn_block
path.write_text(text)
print("Essentials hub spawn + spawn-on-join (/spawn enabled)")
PY
  else
    echo "EssentialsX config not found — start server once after installing EssentialsX.jar"
  fi

  if [[ -f "$TEMPLATES/luckperms-homes-rtp.txt" ]]; then
    echo "Homes + RTP: paste commands from server/config-templates/luckperms-homes-rtp.txt into the console"
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
