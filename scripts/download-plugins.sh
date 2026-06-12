#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGINS_DIR="$ROOT/server/plugins"
TARGET_MC_VERSION="1.21.11"

mkdir -p "$PLUGINS_DIR"

download() {
  local url="$1"
  local output="$2"
  echo "→ $output"
  curl -fsSL "$url" -o "$PLUGINS_DIR/$output"
}

verify_jar() {
  local file="$1"
  if ! unzip -tq "$PLUGINS_DIR/$file" >/dev/null 2>&1; then
    echo "✗ $file is not a valid jar"
    exit 1
  fi
}

modrinth_latest() {
  local project="$1"
  local loader="$2"
  local game_version="$3"
  python3 - "$project" "$loader" "$game_version" <<'PY'
import json, sys, urllib.parse, urllib.request

project, loader, game_version = sys.argv[1:4]
query = urllib.parse.urlencode({
    "loaders": json.dumps([loader]),
    "game_versions": json.dumps([game_version]),
})
url = f"https://api.modrinth.com/v2/project/{project}/version?{query}"
with urllib.request.urlopen(url) as response:
    versions = json.load(response)
if not versions:
    raise SystemExit(f"No Modrinth release for {project} on {loader} {game_version}")
latest = versions[0]
primary = next(f for f in latest["files"] if f["primary"])
print(latest["version_number"])
print(primary["url"])
print(primary["filename"])
PY
}

echo "Downloading Geyser SMP plugins into $PLUGINS_DIR"
echo

# Crossplay (required)
download \
  "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot" \
  "Geyser-Spigot.jar"

download \
  "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot" \
  "Floodgate-Spigot.jar"

# Voice chat
download \
  "https://cdn.modrinth.com/data/9eGKb6K1/versions/7ROzE7Qh/voicechat-bukkit-2.6.18.jar" \
  "voicechat-bukkit-2.6.18.jar"

# Bedrock voice bridge (dev build — no stable 1.0 yet)
download \
  "https://cdn.modrinth.com/data/GJLuArlK/versions/vM2sWM5g/Svg-Spigot-0.1.1-DEV.jar" \
  "SimpleVoice-Geyser.jar"

# Moderation — resolve latest Staff++ build for Paper 1.21.11
STAFF_META="$(modrinth_latest "staff++" "paper" "$TARGET_MC_VERSION")"
STAFF_VERSION="$(echo "$STAFF_META" | sed -n '1p')"
STAFF_URL="$(echo "$STAFF_META" | sed -n '2p')"
STAFF_FILENAME="$(echo "$STAFF_META" | sed -n '3p')"
STAFF_OUTPUT="StaffPlusPlus-${STAFF_VERSION}.jar"
echo "→ $STAFF_OUTPUT (Staff++ $STAFF_VERSION for Paper $TARGET_MC_VERSION)"
curl -fsSL "$STAFF_URL" -o "$PLUGINS_DIR/$STAFF_OUTPUT"
verify_jar "$STAFF_OUTPUT"

# Version support (recommended)
download \
  "https://cdn.modrinth.com/data/P1OZGk5p/versions/N50tHB0H/ViaVersion-5.9.2-SNAPSHOT.jar" \
  "ViaVersion.jar"

download \
  "https://cdn.modrinth.com/data/NpvuJQoq/versions/Ezvt2PhZ/ViaBackwards-5.9.2-SNAPSHOT.jar" \
  "ViaBackwards.jar"

# Permissions + nametag/tab prefixes
download \
  "https://cdn.modrinth.com/data/Vebnzrzj/versions/MBSY8toc/LuckPerms-Bukkit-5.5.53.jar" \
  "LuckPerms.jar"
verify_jar "LuckPerms.jar"

# Nametags + tab list tags (Vanilla jar for Paper 1.21.x)
download \
  "https://github.com/NEZNAMY/TAB/releases/download/6.0.3/TAB.v6.0.3.-.Vanilla.jar" \
  "TAB.jar"
verify_jar "TAB.jar"

# Extras — grief rollback, Discord bridge, web map, placeholders
bash "$ROOT/scripts/download-extras.sh"

echo
echo "Done. Jars saved to server/plugins/"
echo
echo "Verified compatible stack:"
echo "  Paper $TARGET_MC_VERSION"
echo "  Staff++ $STAFF_VERSION (Paper + MC $TARGET_MC_VERSION)"
echo "  LuckPerms (Staff++ soft-dependency for permissions)"
echo "  Simple Voice Chat bukkit 2.6.18"
echo "  SimpleVoice-Geyser 0.1.1-DEV"
echo "  Geyser + Floodgate (keep versions in sync)"
  echo "  CoreProtect, DiscordSRV, BlueMap, PlaceholderAPI"
  echo "  EssentialsX (homes), BetterRTP (random teleport)"
echo
echo "Paper jar: run ./scripts/download-paper.sh (or full ./scripts/debian-setup.sh)"
