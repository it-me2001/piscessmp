#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$ROOT}"
ACCEPT_EULA=false
INSTALL_DEPS=false
CONFIGURE_FIREWALL=false
INSTALL_SYSTEMD=false
INSTALL_TIMERS=false
PRODUCTION=false
SKIP_DOWNLOAD=false

usage() {
  cat <<'EOF'
Pisces SMP — one-shot Debian setup

Usage: ./setup.sh [options]

Options:
  --install-deps     Install apt packages (Java 21, curl, python3, unzip, ufw)
  --firewall         Open Minecraft ports with ufw
  --systemd          Install piscessmp.service and enable on boot
  --timers           Enable auto-update + auto-backup systemd timers
  --production       Full production setup (deps + firewall + systemd + timers)
  --accept-eula      Write eula=true automatically
  --install-dir DIR  Target path (default: repo root)
  --skip-download    Skip Paper/plugin download (config only)
  -h, --help         Show this help

Examples:
  ./setup.sh --production --accept-eula
  sudo ./setup.sh --install-deps --firewall
  ./setup.sh --systemd --timers
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-deps) INSTALL_DEPS=true ;;
    --firewall) CONFIGURE_FIREWALL=true ;;
    --systemd) INSTALL_SYSTEMD=true ;;
    --timers) INSTALL_TIMERS=true ;;
    --production)
      INSTALL_DEPS=true
      CONFIGURE_FIREWALL=true
      INSTALL_SYSTEMD=true
      INSTALL_TIMERS=true
      ;;
    --accept-eula) ACCEPT_EULA=true ;;
    --install-dir) INSTALL_DIR="$2"; shift ;;
    --skip-download) SKIP_DOWNLOAD=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

if [[ "$INSTALL_DIR" != "$ROOT" ]]; then
  echo "Copying project to $INSTALL_DIR..."
  sudo mkdir -p "$INSTALL_DIR"
  sudo rsync -a --exclude server/world --exclude server/logs --exclude 'server/backups' "$ROOT/" "$INSTALL_DIR/"
  ROOT="$INSTALL_DIR"
fi

SERVER_DIR="$ROOT/server"
DEPLOY_DIR="$ROOT/deploy"

step() {
  printf '\n\033[1;36m▸ %s\033[0m\n' "$1"
}

step "Pisces SMP setup"
echo "  Path: $ROOT"

if $INSTALL_DEPS; then
  step "Installing system dependencies"
  sudo bash "$ROOT/scripts/debian-install-deps.sh"
fi

if ! $SKIP_DOWNLOAD; then
  step "Downloading Paper + plugins"
  bash "$ROOT/scripts/debian-setup.sh"
  bash "$ROOT/scripts/update.sh" || true
fi

step "Preparing config templates"
bash "$ROOT/scripts/configure.sh" --prepare

if $ACCEPT_EULA; then
  step "Accepting Minecraft EULA"
  echo 'eula=true' > "$SERVER_DIR/eula.txt"
fi

if [[ ! -f "$DEPLOY_DIR/backup.env" ]]; then
  step "Generating backup/RCON config"
  bash "$ROOT/scripts/configure.sh" --rcon
fi

chmod +x "$ROOT"/setup.sh "$ROOT"/scripts/*.sh "$ROOT"/scripts/update-lib.py 2>/dev/null || true

if $CONFIGURE_FIREWALL; then
  step "Configuring firewall"
  sudo bash "$ROOT/scripts/debian-firewall.sh"
fi

if $INSTALL_SYSTEMD || $INSTALL_TIMERS; then
  step "Installing systemd units"
  sudo cp "$DEPLOY_DIR/piscessmp.service" /etc/systemd/system/
  if $INSTALL_TIMERS; then
    sudo cp "$DEPLOY_DIR/piscessmp-update.service" /etc/systemd/system/
    sudo cp "$DEPLOY_DIR/piscessmp-update.timer" /etc/systemd/system/
    sudo cp "$DEPLOY_DIR/piscessmp-backup.service" /etc/systemd/system/
    sudo cp "$DEPLOY_DIR/piscessmp-backup.timer" /etc/systemd/system/
  fi
  if [[ -f "$DEPLOY_DIR/backup.env" ]]; then
    sudo mkdir -p /opt/piscessmp/deploy 2>/dev/null || true
    sudo cp "$DEPLOY_DIR/backup.env" /etc/piscessmp-backup.env 2>/dev/null || \
      sudo cp "$DEPLOY_DIR/backup.env" "$DEPLOY_DIR/backup.env.installed"
  fi
  sudo sed -i "s|/opt/piscessmp|$ROOT|g" /etc/systemd/system/piscessmp.service
  if $INSTALL_TIMERS; then
    sudo sed -i "s|/opt/piscessmp|$ROOT|g" /etc/systemd/system/piscessmp-*.service
    sudo sed -i "s|/opt/piscessmp|$ROOT|g" /etc/systemd/system/piscessmp-backup.service 2>/dev/null || true
    sudo sed -i "s|EnvironmentFile=-/opt/piscessmp/deploy/backup.env|EnvironmentFile=-$DEPLOY_DIR/backup.env|" \
      /etc/systemd/system/piscessmp-backup.service
  fi
  sudo systemctl daemon-reload
  if $INSTALL_SYSTEMD; then
    sudo systemctl enable piscessmp
    echo "  Enabled piscessmp.service (start with: sudo systemctl start piscessmp)"
  fi
  if $INSTALL_TIMERS; then
    sudo systemctl enable --now piscessmp-update.timer
    sudo systemctl enable --now piscessmp-backup.timer
    echo "  Enabled update + backup timers"
  fi
fi

cat <<EOF

\033[1;32m✓ Setup complete\033[0m

\033[1mNext steps\033[0m
  1. Accept EULA (if you haven't):
       echo 'eula=true' > server/eula.txt
  2. Start the server:
       ./scripts/start.sh
       # or: sudo systemctl start piscessmp
  3. After first start, apply plugin configs:
       ./scripts/configure.sh --apply
  4. Set staff ranks (in server console):
       /lp group staff permission set staff.* true
       /lp user <name> parent set staff

\033[1mConnect\033[0m
  Java:    your-ip:25565
  Bedrock: your-ip:19132

\033[1mUseful commands\033[0m
  ./scripts/update.sh --check
  ./scripts/backup.sh
  sudo systemctl status piscessmp

EOF
