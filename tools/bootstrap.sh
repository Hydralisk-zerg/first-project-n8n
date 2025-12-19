#!/usr/bin/env bash
set -euo pipefail

# NOTE: Kept for reference. Primary entrypoint is scripts/bootstrap.ps1.

# Simple cross-distro bootstrap for Docker + project deploy
# Supports:
# - Debian/Ubuntu (apt)
# - RHEL/CentOS/Rocky/Alma (yum/dnf)
# - macOS (Homebrew + Docker Desktop guidance)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}==>${NC} $*"; }
warn() { echo -e "${YELLOW}WARN${NC}: $*"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

install_docker_debian() {
  log "Installing Docker Engine (apt)"
  sudo apt-get update -y
  sudo apt-get install -y docker.io docker-compose-plugin
  sudo systemctl enable --now docker
}

install_docker_rhel() {
  log "Installing Docker Engine (yum/dnf)"
  if need_cmd dnf; then PKG=dnf; else PKG=yum; fi
  sudo $PKG -y install docker docker-compose-plugin || sudo $PKG -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin || true
  sudo systemctl enable --now docker || true
}

install_docker_macos() {
  if ! need_cmd brew; then
    warn "Homebrew not found. Install from https://brew.sh then rerun."
    exit 1
  fi
  log "Installing Docker Desktop (brew cask)"
  brew install --cask docker || true
  open -a Docker || true
  warn "Docker Desktop needs user confirmation and may take a while to start."
}

wait_for_docker() {
  log "Waiting for Docker to be ready..."
  for i in $(seq 1 60); do
    if docker version >/dev/null 2>&1; then return 0; fi
    sleep 3
  done
  echo "Docker did not become ready in time" >&2
  exit 1
}

case "$(uname -s)" in
  Linux)
    if [ -f /etc/debian_version ]; then
      install_docker_debian
    elif [ -f /etc/redhat-release ] || [ -f /etc/centos-release ]; then
      install_docker_rhel
    else
      warn "Unsupported Linux distro. Please install Docker Engine manually."
    fi
    ;;
  Darwin)
    install_docker_macos
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

wait_for_docker

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
cd "$PROJECT_DIR"

if [ ! -f .env ]; then
  cp -f .env.example .env
  echo -e "${YELLOW}Created .env from template. Please edit .env and rerun if needed.${NC}"
fi

if grep -q '^ENCRYPTION_KEY=CHANGE_ME_GENERATED' .env || ! grep -q '^ENCRYPTION_KEY=' .env; then
  HEX=$(openssl rand -hex 32 2>/dev/null || cat /proc/sys/kernel/random/uuid | tr -d '-')
  sed -i.bak "s/^ENCRYPTION_KEY=.*/ENCRYPTION_KEY=${HEX}/" .env || echo "ENCRYPTION_KEY=${HEX}" >> .env
  log "Generated ENCRYPTION_KEY"
fi

log "Pulling images"
docker compose pull || true
log "Starting containers"
docker compose up -d
log "Tail last 50 n8n logs"
docker compose logs n8n --tail 50 || true

echo -e "${GREEN}Done.${NC}"
