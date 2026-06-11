#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$ROOT/server"
TARGET_MC_VERSION="${PAPER_VERSION:-1.21.11}"
USER_AGENT="piscessmp/1.0 (debian-setup)"
JAR_PATH="$SERVER_DIR/paper.jar"

mkdir -p "$SERVER_DIR"

python3 - "$TARGET_MC_VERSION" "$JAR_PATH" "$USER_AGENT" <<'PY'
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

version, jar_path, user_agent = sys.argv[1:4]
api = f"https://fill.papermc.io/v3/projects/paper/versions/{version}/builds"
req = urllib.request.Request(api, headers={"User-Agent": user_agent})

with urllib.request.urlopen(req) as response:
    builds = json.load(response)

stable = [b for b in builds if b.get("channel") == "STABLE"]
latest = (stable or builds)[-1]
download = latest["downloads"]["server:default"]
url = download["url"]
expected_sha = download["checksums"]["sha256"]
build_id = latest["id"]

print(f"Paper {version} build {build_id}")
print(f"Downloading {url}")

tmp_path = Path(jar_path + ".tmp")
with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": user_agent})) as response:
    data = response.read()

if len(data) < 5_000_000:
    raise SystemExit("Download too small — likely not a valid Paper jar")

actual_sha = hashlib.sha256(data).hexdigest()
if actual_sha != expected_sha:
    raise SystemExit(f"SHA256 mismatch\nexpected: {expected_sha}\nactual:   {actual_sha}")

tmp_path.write_bytes(data)
tmp_path.replace(jar_path)
print(f"Saved {jar_path}")
PY
