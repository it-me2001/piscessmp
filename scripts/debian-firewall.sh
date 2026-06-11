#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo ./scripts/debian-firewall.sh"
  exit 1
fi

# Minecraft Java
ufw allow 25565/tcp comment 'Minecraft Java'

# Geyser Bedrock (UDP only)
ufw allow 19132/udp comment 'Geyser Bedrock'

# Simple Voice Chat
ufw allow 24454/udp comment 'Simple Voice Chat'

# SimpleVoice-Geyser web UI
ufw allow 8080/tcp comment 'Voice web UI'

echo "Firewall rules added. Enable ufw if not active:"
echo "  ufw enable"
ufw status numbered
