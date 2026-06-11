#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo ./scripts/debian-install-deps.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update

PACKAGES=(
  bash
  ca-certificates
  curl
  jq
  python3
  unzip
  ufw
)

# Java 21 — required for Paper 1.21.x
if apt-cache show openjdk-21-jre-headless &>/dev/null; then
  PACKAGES+=(openjdk-21-jre-headless)
elif apt-cache show openjdk-21-jre &>/dev/null; then
  PACKAGES+=(openjdk-21-jre)
else
  echo "openjdk-21 not found in apt."
  echo "Debian 12: enable bookworm-backports, then re-run:"
  echo "  echo 'deb http://deb.debian.org/debian bookworm-backports main' > /etc/apt/sources.list.d/backports.list"
  echo "  apt-get update && apt-get install -t bookworm-backports openjdk-21-jre-headless"
  exit 1
fi

apt-get install -y "${PACKAGES[@]}"

java -version
echo "Debian dependencies installed."
