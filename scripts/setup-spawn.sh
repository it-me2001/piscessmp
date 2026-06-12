#!/usr/bin/env bash
# Separate spawn hub world + survival overworld.
# - Creates flat "spawn" world (Multiverse), pastes hub schematic there
# - Keeps "world" as survival; /rtp and homes stay in world
# - Essentials /spawn → hub; /warp survival → overworld
#
# Run on VPS: sudo bash /opt/piscessmp/scripts/setup-spawn.sh
# Optional env:
#   SCHEM_URL=https://.../MyHub.schem   # direct .schem download (200x200+ builds)
#   SCHEM_PATH=/path/to/local.schem     # use local file instead of URL
#   SCHEM_NAME=pisces-spawn
#   SPAWN_WORLD=spawn
#   SURVIVAL_WORLD=world
#   SKIP_UFW=1                          # skip firewall reset
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$ROOT/server"
PLUGINS_DIR="$SERVER_DIR/plugins"
SCHEM_DIR="$PLUGINS_DIR/WorldEdit/schematics"
SCHEM_NAME="${SCHEM_NAME:-pisces-spawn}"
SCHEM_URL="${SCHEM_URL:-https://raw.githubusercontent.com/katorlys/WintertimeSpawn/main/WintertimeSpawn.schem}"
SCHEM_PATH="${SCHEM_PATH:-$ROOT/server/assets/pisces-spawn.schem}"
SPAWN_WORLD="${SPAWN_WORLD:-spawn}"
SURVIVAL_WORLD="${SURVIVAL_WORLD:-world}"
SPAWN_X=0
SPAWN_Y=64
SPAWN_Z=0
SURVIVAL_SPAWN_X=1024
SURVIVAL_SPAWN_Y=100
SURVIVAL_SPAWN_Z=1024
WORLDEDIT_URL="https://cdn.modrinth.com/data/1u6JkXh5/versions/yDUBafTJ/worldedit-bukkit-7.4.3.jar"
MULTIVERSE_URL="https://hangarcdn.papermc.io/plugins/Multiverse/Multiverse-Core/versions/5.7.0/PAPER/multiverse-core-5.7.0.jar"
FORCELOAD_RADIUS="${FORCELOAD_RADIUS:-8}" # chunks each direction (~200x200 build)

rcon() {
  local cmd="$1"
  if [[ ! -f "$ROOT/deploy/backup.env" ]]; then
    echo "skip rcon (no backup.env): $cmd"
    return 0
  fi
  # shellcheck source=/dev/null
  source "$ROOT/deploy/backup.env"
  mcrcon -H 127.0.0.1 -P "${RCON_PORT:-25575}" -p "$RCON_PASSWORD" "$cmd" || true
  sleep 2
}

echo "=== Plugins: WorldEdit + Multiverse-Core ==="
mkdir -p "$SCHEM_DIR" "$ROOT/server/assets"
if [[ ! -f "$PLUGINS_DIR/WorldEdit.jar" ]] && ! compgen -G "$PLUGINS_DIR/worldedit-bukkit"*.jar >/dev/null; then
  curl -fsSL "$WORLDEDIT_URL" -o "$PLUGINS_DIR/WorldEdit.jar"
  echo "Installed WorldEdit.jar"
fi
if [[ ! -f "$PLUGINS_DIR/Multiverse-Core.jar" ]] && ! compgen -G "$PLUGINS_DIR/multiverse-core"*.jar >/dev/null; then
  curl -fsSL "$MULTIVERSE_URL" -o "$PLUGINS_DIR/Multiverse-Core.jar"
  echo "Installed Multiverse-Core.jar"
fi

echo "=== Spawn schematic ==="
if [[ -f "$SCHEM_PATH" ]]; then
  cp "$SCHEM_PATH" "$SCHEM_DIR/${SCHEM_NAME}.schem"
  echo "Using local schematic: $SCHEM_PATH"
else
  curl -fsSL "$SCHEM_URL" -o "$SCHEM_DIR/${SCHEM_NAME}.schem"
  echo "Downloaded ${SCHEM_NAME}.schem from SCHEM_URL"
  echo "  Tip: drop a 150x200+ .schem at server/assets/pisces-spawn.schem and re-run"
fi
chown -R minecraft:minecraft "$PLUGINS_DIR/WorldEdit" "$SCHEM_DIR" 2>/dev/null || true

if [[ "${SKIP_UFW:-0}" != "1" ]]; then
  echo "=== UFW cleanup ==="
  ufw allow 22/tcp comment 'SSH' >/dev/null 2>&1 || true
  ufw allow 25565/tcp comment 'Minecraft Java' >/dev/null 2>&1 || true
  ufw allow 19132/udp comment 'Geyser Bedrock' >/dev/null 2>&1 || true
  ufw status verbose || true
fi

echo "=== Restart server to load plugins ==="
systemctl restart piscessmp
echo "Waiting 90s for boot..."
sleep 90

echo "=== Create spawn hub world (Multiverse) ==="
if [[ ! -d "$SERVER_DIR/$SPAWN_WORLD" ]]; then
  rcon "mv create $SPAWN_WORLD normal -t FLAT"
else
  echo "World $SPAWN_WORLD already exists — skipping mv create"
fi
rcon "mv modify set spawn true $SPAWN_WORLD"
rcon "mv modify set gamemode adventure $SPAWN_WORLD"
rcon "mv modify set difficulty peaceful $SPAWN_WORLD"
rcon "mv modify set animals false $SPAWN_WORLD"
rcon "mv modify set monsters false $SPAWN_WORLD"
rcon "mv modify set pvp false $SPAWN_WORLD"
rcon "execute in minecraft:${SPAWN_WORLD} run gamerule randomTickSpeed 0"

echo "=== Survival world spawn (away from old hub paste) ==="
rcon "execute in minecraft:${SURVIVAL_WORLD} run setworldspawn ${SURVIVAL_SPAWN_X} ${SURVIVAL_SPAWN_Y} ${SURVIVAL_SPAWN_Z}"

echo "=== Load chunks + paste hub in $SPAWN_WORLD ==="
rcon "save-all flush"
for cx in $(seq "-$FORCELOAD_RADIUS" "$FORCELOAD_RADIUS"); do
  for cz in $(seq "-$FORCELOAD_RADIUS" "$FORCELOAD_RADIUS"); do
    rcon "execute in minecraft:${SPAWN_WORLD} run forceload add $cx $cz"
  done
done
sleep 8
rcon "execute in minecraft:${SPAWN_WORLD} run gamerule randomTickSpeed 0"
rcon "//world ${SPAWN_WORLD}"
rcon "//schem load ${SCHEM_NAME}.schem"
sleep 2
rcon "//paste -a"
rcon "execute in minecraft:${SPAWN_WORLD} run setworldspawn ${SPAWN_X} $((SPAWN_Y + 1)) ${SPAWN_Z}"

echo "=== Essentials: hub spawn + survival warp ==="
ESS_CONFIG="$PLUGINS_DIR/Essentials/config.yml"
WARPS_FILE="$PLUGINS_DIR/Essentials/warps.yml"
if [[ -f "$ESS_CONFIG" ]]; then
  python3 - "$ESS_CONFIG" "$SPAWN_WORLD" "$SPAWN_X" "$SPAWN_Y" "$SPAWN_Z" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
world, x, y, z = sys.argv[2:7]
text = path.read_text()
text = re.sub(r"spawn-on-join:\s*false", "spawn-on-join: true", text)
if "spawn-on-join:" not in text:
    text += "\nspawn-on-join: true\n"
spawn_block = f"""
spawns:
  default:
    world: {world}
    x: {float(x) + 0.5}
    y: {float(y) + 1.0}
    z: {float(z) + 0.5}
    yaw: 0.0
    pitch: 0.0
"""
if "spawns:" not in text:
    text += spawn_block
else:
    text = re.sub(
        r"spawns:\s*\n\s*default:\s*\n(?:\s+\w+:.*\n)+",
        spawn_block.strip() + "\n",
        text,
        count=1,
    )
path.write_text(text)
print("Patched Essentials hub spawn")
PY
  chown minecraft:minecraft "$ESS_CONFIG" 2>/dev/null || true
fi

if [[ -f "$WARPS_FILE" ]]; then
  python3 - "$WARPS_FILE" "$SURVIVAL_WORLD" "$SURVIVAL_SPAWN_X" "$SURVIVAL_SPAWN_Y" "$SURVIVAL_SPAWN_Z" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
world, x, y, z = sys.argv[2:7]
text = path.read_text()
block = f"""survival:
  world: {world}
  x: {float(x) + 0.5}
  y: {float(y) + 0.0}
  z: {float(z) + 0.5}
  yaw: 0.0
  pitch: 0.0
"""
if "survival:" in text:
    text = re.sub(r"survival:\s*\n(?:\s+\w+:.*\n)+", block, text, count=1)
else:
    text = text.rstrip() + "\n\n" + block
path.write_text(text if text.endswith("\n") else text + "\n")
print("Added Essentials warp: survival")
PY
  chown minecraft:minecraft "$WARPS_FILE" 2>/dev/null || true
else
  cat > "$WARPS_FILE" <<EOF
survival:
  world: ${SURVIVAL_WORLD}
  x: $(python3 -c "print(${SURVIVAL_SPAWN_X} + 0.5)")
  y: ${SURVIVAL_SPAWN_Y}.0
  z: $(python3 -c "print(${SURVIVAL_SPAWN_Z} + 0.5)")
  yaw: 0.0
  pitch: 0.0
EOF
  chown minecraft:minecraft "$WARPS_FILE" 2>/dev/null || true
  echo "Created Essentials warps.yml with survival warp"
fi

echo "=== BetterRTP: survival world only ==="
BETTERRTP="$PLUGINS_DIR/BetterRTP/config.yml"
if [[ -f "$BETTERRTP" ]]; then
  python3 - "$BETTERRTP" "$SPAWN_WORLD" "$SURVIVAL_WORLD" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
spawn_world, survival_world = sys.argv[2:4]
text = path.read_text()
if f"- {spawn_world}" not in text:
    needle = "DisabledWorlds:\n"
    if needle in text and f"- {spawn_world}\n" not in text:
        text = text.replace(needle, needle + f"- {spawn_world}\n", 1)
if f"World: {survival_world}" not in text:
    import re
    text = re.sub(r"World:\s*\S+", f"World: {survival_world}", text, count=1)
path.write_text(text)
print("BetterRTP: disabled in hub, RTP targets survival")
PY
  chown minecraft:minecraft "$BETTERRTP" 2>/dev/null || true
fi

echo "=== LuckPerms: multiverse + survival warp ==="
rcon "lp group default permission set multiverse.access.${SPAWN_WORLD} true"
rcon "lp group default permission set multiverse.access.${SURVIVAL_WORLD} true"
rcon "lp group default permission set multiverse.teleport.self.${SURVIVAL_WORLD} true"
rcon "lp group default permission set essentials.warps.survival true"

rcon "essentials reload"
rcon "betterrtp reload"
rcon "save-all flush"
systemctl restart piscessmp

echo ""
echo "Done."
echo "  Hub world:     ${SPAWN_WORLD} (adventure, peaceful, schematic pasted)"
echo "  Survival:      ${SURVIVAL_WORLD} (homes, RTP, building)"
echo "  /spawn         → hub"
echo "  /warp survival → survival overworld"
echo "  /rtp           → random location in ${SURVIVAL_WORLD} only"
echo ""
echo "Bigger schematic: place server/assets/pisces-spawn.schem or set SCHEM_URL=... and re-run."
