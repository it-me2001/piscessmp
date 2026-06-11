#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$ROOT/server"
JAR="$SERVER_DIR/paper.jar"
cd "$SERVER_DIR"

if [[ ! -f "$JAR" ]]; then
  echo "Missing $JAR — run ./scripts/debian-setup.sh first"
  exit 1
fi

if [[ ! -f eula.txt ]] || ! grep -q '^eula=true' eula.txt; then
  echo "Accept the Minecraft EULA first:"
  echo "  echo 'eula=true' > $SERVER_DIR/eula.txt"
  exit 1
fi

if [[ "${UPDATE_ON_START:-false}" == "true" ]]; then
  echo "Checking for updates (UPDATE_ON_START=true)..."
  bash "$ROOT/scripts/update.sh" || true
fi

: "${JAVA:=java}"
: "${MEMORY_MIN:=4G}"
: "${MEMORY_MAX:=4G}"

exec "$JAVA" -Xms"$MEMORY_MIN" -Xmx"$MEMORY_MAX" \
  -XX:+UseG1GC \
  -XX:+ParallelRefProcEnabled \
  -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+DisableExplicitGC \
  -XX:+AlwaysPreTouch \
  -XX:G1NewSizePercent=30 \
  -XX:G1MaxNewSizePercent=40 \
  -XX:G1HeapRegionSize=8M \
  -XX:G1ReservePercent=20 \
  -XX:G1HeapWastePercent=5 \
  -XX:G1MixedGCCountTarget=4 \
  -XX:InitiatingHeapOccupancyPercent=15 \
  -XX:G1MixedGCLiveThresholdPercent=90 \
  -XX:G1RSetUpdatingPauseTimePercent=5 \
  -XX:SurvivorRatio=32 \
  -XX:+PerfDisableSharedMem \
  -XX:MaxTenuringThreshold=1 \
  -Dusing.aikars.flags=https://mcflags.emc.gs \
  -Daikars.new.flags=true \
  -jar "$JAR" nogui
