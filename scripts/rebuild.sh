#!/usr/bin/env bash
# ==============================================================================
# rebuild.sh — Pull latest code, rebuild, and restart Enumethod services
#
# Usage:
#   sudo ./rebuild.sh
#
# Runs from the repo or /opt/enumethod
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${RED}[!]${NC} $*"; }
step() { echo -e "\n${BOLD}${CYAN}── $* ──${NC}"; }

APP_DIR="/opt/enumethod"

if [ "$(id -u)" -ne 0 ]; then
    warn "Must run as root"
    exit 1
fi

if [ ! -d "$APP_DIR" ]; then
    warn "$APP_DIR not found — run deploy.sh first"
    exit 1
fi

cd "$APP_DIR"

step "Pulling latest code"
if [ -d ".git" ]; then
    git pull
else
    warn "Not a git repo — skipping pull"
fi

step "Installing dependencies"
pnpm install --frozen-lockfile 2>/dev/null || pnpm install

step "Running Prisma generate + schema sync"
set -a; source "$APP_DIR/.env"; set +a
pnpm exec prisma generate
pnpm exec prisma db push --accept-data-loss

step "Building application"
pnpm exec turbo build

step "Restarting services"
chown -R www-data:www-data "$APP_DIR"
chown root:root "$APP_DIR/enumerate.sh"
chmod 755 "$APP_DIR/enumerate.sh"

systemctl restart enumethod-api
systemctl restart enumethod-web

log "Rebuild complete"
echo ""
echo -e "  ${BOLD}Services:${NC}"
systemctl --no-pager status enumethod-api | head -3
echo ""
systemctl --no-pager status enumethod-web | head -3
echo ""
