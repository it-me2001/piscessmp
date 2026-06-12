#!/usr/bin/env bash
# Migrate Pisces SMP from systemd to Docker Compose.
# Run on the VPS as root: sudo bash scripts/docker-migrate.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

step() { printf '\n\033[1;36m▸ %s\033[0m\n' "$1"; }

step "Pull latest repo"
git pull origin main

step "Create docker.env from deploy/backup.env"
if [[ ! -f "$ROOT/deploy/backup.env" ]]; then
  echo "Missing deploy/backup.env — copy from deploy/backup.env.example and set RCON_PASSWORD"
  exit 1
fi
# shellcheck source=/dev/null
source "$ROOT/deploy/backup.env"
cat > "$ROOT/docker.env" <<EOF
ACCEPT_EULA=true
MEMORY_MIN=4G
MEMORY_MAX=4G
RCON_PASSWORD=${RCON_PASSWORD}
UPDATE_ON_START=false
JAVA_PORT=25565
BEDROCK_PORT=19132
RCON_PORT=${RCON_PORT:-25575}
VOICE_PORT=24454
VOICE_WEB_PORT=8080
BLUEMAP_PORT=8100
EOF
chmod 600 "$ROOT/docker.env"
echo "Wrote docker.env"

step "Stop systemd service (free port 25565)"
systemctl stop piscessmp 2>/dev/null || true
systemctl disable piscessmp 2>/dev/null || true

step "Build and start Docker"
docker compose down 2>/dev/null || true
docker compose build
docker compose up -d

step "Waiting for server boot..."
for i in $(seq 1 30); do
  if docker compose exec -T piscessmp bash -c 'nc -z localhost 25565' 2>/dev/null; then
    echo "Server is listening on 25565"
    break
  fi
  sleep 10
done

docker compose ps
echo ""
echo "Done. Pisces SMP is running in Docker."
echo "  Logs:    docker compose -f $ROOT/docker-compose.yml logs -f"
echo "  Stop:    docker compose -f $ROOT/docker-compose.yml down"
echo "  Restart: docker compose -f $ROOT/docker-compose.yml restart"
echo "  Backup:  docker compose -f $ROOT/docker-compose.yml exec piscessmp ./scripts/backup.sh"
echo "  Update:  docker compose -f $ROOT/docker-compose.yml exec piscessmp ./scripts/update.sh --restart"
