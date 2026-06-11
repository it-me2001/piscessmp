#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_DIR="$ROOT/deploy"
DOMAIN_ENV="$DEPLOY_DIR/domain.env"
CADDY_DIR="/etc/caddy"
CADDYFILE="$CADDY_DIR/Caddyfile"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo ./scripts/setup-caddy.sh"
  exit 1
fi

if [[ ! -f "$DOMAIN_ENV" ]]; then
  echo "Missing $DOMAIN_ENV"
  echo "Copy deploy/domain.env.example → deploy/domain.env and set DOMAIN + ACME_EMAIL"
  exit 1
fi

# shellcheck source=/dev/null
source "$DOMAIN_ENV"

if [[ -z "${DOMAIN:-}" ]] || [[ "$DOMAIN" == *"example.com"* ]]; then
  echo "Set a real DOMAIN in deploy/domain.env"
  exit 1
fi

: "${ACME_EMAIL:?Set ACME_EMAIL in deploy/domain.env}"
: "${VOICE_HOST:=voice.$DOMAIN}"
: "${MAP_HOST:=map.$DOMAIN}"

export VOICE_HOST MAP_HOST ACME_EMAIL

apt-get update
apt-get install -y caddy debian-keyring debian-archive-keyring apt-transport-https 2>/dev/null || \
  apt-get install -y caddy

mkdir -p "$CADDY_DIR"
envsubst < "$DEPLOY_DIR/caddy/Caddyfile.example" > "$CADDYFILE"

systemctl enable caddy
systemctl restart caddy

ufw allow 80/tcp comment 'Caddy HTTP' 2>/dev/null || true
ufw allow 443/tcp comment 'Caddy HTTPS' 2>/dev/null || true

cat <<EOF

Caddy configured.

  Voice: https://$VOICE_HOST  → localhost:8080
  Map:   https://$MAP_HOST    → localhost:8100

Point DNS A records for $VOICE_HOST and $MAP_HOST to this server's IP.

EOF
