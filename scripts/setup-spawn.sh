#!/usr/bin/env bash
# UFW cleanup + WorldEdit + preset spawn schematic + Essentials spawn config.
# Run on the VPS as root: sudo bash /opt/piscessmp/scripts/setup-spawn.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$ROOT/server"
PLUGINS_DIR="$SERVER_DIR/plugins"
SCHEM_DIR="$PLUGINS_DIR/WorldEdit/schematics"
SCHEM_NAME="pisces-spawn"
SCHEM_URL="https://raw.githubusercontent.com/katorlys/SummertimeSpawn/main/SummertimeSpawn.schem"
WORLDEDIT_URL="https://cdn.modrinth.com/data/1u6JkXh5/versions/yDUBafTJ/worldedit-bukkit-7.4.3.jar"
SPAWN_X=0
SPAWN_Y=64
SPAWN_Z=0

rcon() {
  local cmd="$1"
  if [[ ! -f "$ROOT/deploy/backup.env" ]]; then
    echo "skip rcon (no backup.env): $cmd"
    return 0
  fi
  # shellcheck source=/dev/null
  source "$ROOT/deploy/backup.env"
  mcrcon -H 127.0.0.1 -P "${RCON_PORT:-25575}" -p "$RCON_PASSWORD" "$cmd" || true
}

echo "=== UFW cleanup ==="
ufw allow 22/tcp comment 'SSH' >/dev/null 2>&1 || true
while ufw status numbered 2>/dev/null | grep -qE '^\['; do
  num=$(ufw status numbered | tail -1 | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
  [ -n "$num" ] || break
  echo y | ufw delete "$num" >/dev/null 2>&1 || break
done
ufw default deny incoming >/dev/null 2>&1 || true
ufw default allow outgoing >/dev/null 2>&1 || true
ufw allow 22/tcp comment 'SSH'
ufw allow 25565/tcp comment 'Minecraft Java'
ufw allow 19132/udp comment 'Geyser Bedrock'
ufw allow 24454/udp comment 'Simple Voice Chat'
ufw allow 80/tcp comment 'Caddy HTTP'
ufw allow 443/tcp comment 'Caddy HTTPS'
ufw allow 3001/tcp comment 'clipfarmlabs'
ufw --force enable
ufw status verbose

echo "=== WorldEdit + spawn schematic ==="
mkdir -p "$SCHEM_DIR"
if [[ ! -f "$PLUGINS_DIR/WorldEdit.jar" ]] && [[ ! -f "$PLUGINS_DIR/worldedit-bukkit"*.jar ]]; then
  curl -fsSL "$WORLDEDIT_URL" -o "$PLUGINS_DIR/WorldEdit.jar"
  echo "Installed WorldEdit.jar"
fi
curl -fsSL "$SCHEM_URL" -o "$SCHEM_DIR/${SCHEM_NAME}.schem"
chown -R minecraft:minecraft "$PLUGINS_DIR/WorldEdit" 2>/dev/null || true
echo "Downloaded ${SCHEM_NAME}.schem (SummertimeSpawn — beach hub, CC BY-NC-ND, non-commercial)"

echo "=== Restart server to load WorldEdit ==="
systemctl restart piscessmp
echo "Waiting 90s for boot..."
sleep 90

echo "=== Flatten + paste spawn via RCON ==="
rcon "save-all flush"
# Flatten ~80x80 pad at y=63
rcon "execute in minecraft:overworld run fill ${SPAWN_X} 63 ${SPAWN_Z} $((SPAWN_X + 79)) 63 $((SPAWN_Z + 79)) grass_block"
rcon "execute in minecraft:overworld run fill ${SPAWN_X} 64 ${SPAWN_Z} $((SPAWN_X + 79)) 80 $((SPAWN_Z + 79)) air"
# WorldEdit 7.4 console schematic commands
rcon "schem load ${SCHEM_NAME}"
rcon "tp @a ${SPAWN_X}.5 ${SPAWN_Y} ${SPAWN_Z}.5"
sleep 2
rcon "//paste -a"
rcon "setworldspawn ${SPAWN_X} $((SPAWN_Y + 1)) ${SPAWN_Z}"

echo "=== Essentials spawn config ==="
ESS_CONFIG="$PLUGINS_DIR/Essentials/config.yml"
if [[ -f "$ESS_CONFIG" ]]; then
  python3 - "$ESS_CONFIG" "$SPAWN_X" "$SPAWN_Y" "$SPAWN_Z" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
x, y, z = sys.argv[2:5]
text = path.read_text()
if "spawn-on-join:" in text:
    text = text.replace("spawn-on-join: false", "spawn-on-join: true")
elif "spawn-on-join:" not in text:
    text += "\nspawn-on-join: true\n"
spawn_block = f"""
spawns:
  default:
    world: world
    x: {float(x) + 0.5}
    y: {float(y) + 1.0}
    z: {float(z) + 0.5}
    yaw: 0.0
    pitch: 0.0
"""
if "spawns:" not in text:
    text += spawn_block
path.write_text(text)
print("Patched Essentials spawn + spawn-on-join")
PY
  chown minecraft:minecraft "$ESS_CONFIG" 2>/dev/null || true
fi

rcon "essentials reload"
rcon "save-all flush"
systemctl restart piscessmp

echo ""
echo "Done. Join and test:"
echo "  /spawn"
echo "  If build is missing, stand at spawn and run: //schem load ${SCHEM_NAME}  then  //paste -a"
echo "  Then: /setspawn"
