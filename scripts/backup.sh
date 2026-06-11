#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$ROOT/server"
BACKUP_ROOT="${BACKUP_DIR:-$SERVER_DIR/backups/worlds}"
RETAIN="${BACKUP_RETAIN:-7}"
OFFLINE=false
CHECK=false

usage() {
  cat <<'EOF'
Usage: ./scripts/backup.sh [options]

Creates a compressed backup of worlds, plugin data, and server configs.

Options:
  --check       List what would be backed up
  --offline     Stop piscessmp service before backup, then restart
  --retain N    Keep last N backups (default: 7, or BACKUP_RETAIN env)
  -h, --help    Show this help

Environment (optional):
  RCON_PASSWORD   If set, runs "save-all flush" before backup while server is online
  RCON_HOST       Default: 127.0.0.1
  RCON_PORT       Default: 25575
  BACKUP_RETAIN   Number of backups to keep
  BACKUP_DIR      Output directory (default: server/backups/worlds)

Enable RCON in server/server.properties:
  enable-rcon=true
  rcon.port=25575
  rcon.password=<your-password>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=true ;;
    --offline) OFFLINE=true ;;
    --retain) RETAIN="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

if [[ ! -d "$SERVER_DIR" ]]; then
  echo "Missing server directory: $SERVER_DIR"
  exit 1
fi

ITEMS=()
add_if_exists() {
  local path="$1"
  if [[ -e "$SERVER_DIR/$path" ]]; then
    ITEMS+=("$path")
  fi
}

add_if_exists "world"
add_if_exists "world_nether"
add_if_exists "world_the_end"
add_if_exists "plugins"
add_if_exists "server.properties"
add_if_exists "bukkit.yml"
add_if_exists "spigot.yml"
add_if_exists "paper-global.yml"
add_if_exists "paper-world-defaults.yml"
add_if_exists "ops.json"
add_if_exists "whitelist.json"
add_if_exists "banned-players.json"
add_if_exists "banned-ips.json"
add_if_exists "usercache.json"

if [[ ${#ITEMS[@]} -eq 0 ]]; then
  echo "Nothing to back up yet — start the server once to generate world data."
  exit 0
fi

if $CHECK; then
  echo "Backup source: $SERVER_DIR"
  echo "Backup target: $BACKUP_ROOT"
  echo "Items:"
  printf '  %s\n' "${ITEMS[@]}"
  echo "Retention: keep last $RETAIN backups"
  exit 0
fi

STOPPED=false
start_server() {
  if $STOPPED && command -v systemctl >/dev/null 2>&1; then
    echo "Starting piscessmp service..."
    sudo systemctl start piscessmp
  fi
}

trap start_server EXIT

if $OFFLINE && command -v systemctl >/dev/null 2>&1; then
  if systemctl is-active --quiet piscessmp 2>/dev/null; then
    echo "Stopping piscessmp for offline backup..."
    sudo systemctl stop piscessmp
    STOPPED=true
  fi
elif [[ -n "${RCON_PASSWORD:-}" ]]; then
  echo "Flushing world saves via RCON..."
  python3 - "$RCON_HOST" "${RCON_PORT:-25575}" "$RCON_PASSWORD" <<'PY' || echo "RCON flush failed — continuing with backup"
import socket, struct, sys

host, port, password = sys.argv[1], int(sys.argv[2]), sys.argv[3]

def packet(req_id: int, ptype: int, payload: str) -> bytes:
    body = struct.pack("<ii", req_id, ptype) + payload.encode("utf-8") + b"\x00\x00"
    return struct.pack("<i", len(body)) + body

def recv_packet(sock: socket.socket) -> tuple[int, int, str]:
    raw_len = sock.recv(4)
    if len(raw_len) < 4:
        raise RuntimeError("RCON connection closed")
    (length,) = struct.unpack("<i", raw_len)
    data = b""
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            raise RuntimeError("RCON connection closed")
        data += chunk
    req_id, ptype = struct.unpack("<ii", data[:8])
    text = data[8:-2].decode("utf-8", errors="replace")
    return req_id, ptype, text

with socket.create_connection((host, port), timeout=5) as sock:
    sock.sendall(packet(1, 3, password))
    req_id, ptype, _ = recv_packet(sock)
    if req_id == -1:
        raise RuntimeError("RCON authentication failed")
    sock.sendall(packet(2, 2, "save-all flush"))
    recv_packet(sock)
PY
else
  echo "Tip: set RCON_PASSWORD or use --offline for safer backups."
fi

mkdir -p "$BACKUP_ROOT"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
ARCHIVE="$BACKUP_ROOT/piscessmp-$STAMP.tar.gz"

echo "Creating $ARCHIVE"
tar -czf "$ARCHIVE" -C "$SERVER_DIR" "${ITEMS[@]}"

BYTES="$(wc -c < "$ARCHIVE" | tr -d ' ')"
echo "Backup complete ($(numfmt --to=iec-i --suffix=B "$BYTES" 2>/dev/null || echo "${BYTES} bytes"))"

COUNT=0
while IFS= read -r old; do
  COUNT=$((COUNT + 1))
  if [[ $COUNT -gt $RETAIN ]]; then
    echo "Removing old backup: $old"
    rm -f "$old"
  fi
done < <(ls -1t "$BACKUP_ROOT"/piscessmp-*.tar.gz 2>/dev/null || true)
