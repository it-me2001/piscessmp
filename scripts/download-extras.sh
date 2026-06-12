#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGINS_DIR="${PLUGINS_DIR:-$ROOT/server/plugins}"
TARGET_MC_VERSION="${TARGET_MC_VERSION:-1.21.11}"

mkdir -p "$PLUGINS_DIR"

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

verify_jar() {
  local file="$1"
  if ! unzip -tq "$PLUGINS_DIR/$file" >/dev/null 2>&1; then
    echo "✗ $file is not a valid jar"
    exit 1
  fi
}

download_modrinth() {
  local name="$1"
  local project="$2"
  local output="$3"
  local meta url
  meta="$(modrinth_latest "$project" "paper" "$TARGET_MC_VERSION")"
  url="$(echo "$meta" | sed -n '2p')"
  echo "→ $output ($name)"
  curl -fsSL "$url" -o "$PLUGINS_DIR/$output"
  verify_jar "$output"
}

download_modrinth "CoreProtect" "coreprotect" "CoreProtect.jar"
download_modrinth "DiscordSRV" "discordsrv" "DiscordSRV.jar"
download_modrinth "BlueMap" "bluemap" "BlueMap.jar"
download_modrinth "PlaceholderAPI" "placeholderapi" "PlaceholderAPI.jar"

echo "→ BetterRTP.jar (Hangar Ronan/BetterRTP)"
BETTERRTP_META="$(python3 - <<'PY'
import json, urllib.parse, urllib.request
query = urllib.parse.urlencode({"limit": 1, "offset": 0, "platform": "PAPER"})
url = f"https://hangar.papermc.io/api/v1/projects/Ronan/BetterRTP/versions?{query}"
with urllib.request.urlopen(url) as response:
    versions = json.load(response)["result"]
latest = versions[0]
paper = latest["downloads"]["PAPER"]
print(latest["name"])
print(paper["downloadUrl"])
PY
)"
BETTERRTP_VERSION="$(echo "$BETTERRTP_META" | sed -n '1p')"
BETTERRTP_URL="$(echo "$BETTERRTP_META" | sed -n '2p')"
echo "→ BetterRTP.jar ($BETTERRTP_VERSION)"
curl -fsSL "$BETTERRTP_URL" -o "$PLUGINS_DIR/BetterRTP.jar"
verify_jar "BetterRTP.jar"

echo "→ EssentialsX.jar (GitHub latest release)"
ESSENTIALS_URL="$(curl -fsSL "https://api.github.com/repos/EssentialsX/Essentials/releases/latest" \
  | python3 -c "import json,sys,re; r=json.load(sys.stdin); a=next(x for x in r['assets'] if re.match(r'^EssentialsX-[\\d.]+\\.jar$', x['name'])); print(a['browser_download_url'])")"
curl -fsSL "$ESSENTIALS_URL" -o "$PLUGINS_DIR/EssentialsX.jar"
verify_jar "EssentialsX.jar"
