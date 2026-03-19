#!/usr/bin/env bash
# ==============================================================================
# deploy.sh — Deploy Enumethod v2 on Ubuntu 24.04 LTS (Linode)
#
# Usage:
#   sudo ./deploy.sh -d <DOMAIN> -e <EMAIL> [OPTIONS]
#
# Required:
#   -d, --domain DOMAIN         FQDN for nginx + SSL
#   -e, --email EMAIL           Email for Let's Encrypt
#
# Optional:
#   --db-password PW            PostgreSQL password (default: random)
#   --node-version VER          Node.js major version (default: 22)
#   --self-signed               Use self-signed SSL instead of Let's Encrypt
#   --cert FILE --key FILE      Use custom certificate
#   --no-ssl                    HTTP only, no SSL
#   -h, --help                  Show this help
#
# All steps are idempotent — safe to re-run.
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${RED}[!]${NC} $*"; }
step() { echo -e "\n${BOLD}${CYAN}── $* ──${NC}"; }

# ── Defaults ─────────────────────────────────────────────────────────────────

DOMAIN=""
EMAIL=""
DB_PASSWORD=""
NODE_VERSION=22
SSL_MODE="letsencrypt"
CUSTOM_CERT=""
CUSTOM_KEY=""
APP_DIR="/opt/enumethod"
SERVICE_USER="www-data"

usage() {
    sed -n '2,/^# =====/{ /^# =====/d; s/^# \?//; p }' "$0"
    exit 0
}

# ── Parse args ───────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--domain)       DOMAIN="$2";       shift 2 ;;
        -e|--email)        EMAIL="$2";        shift 2 ;;
        --db-password)     DB_PASSWORD="$2";  shift 2 ;;
        --node-version)    NODE_VERSION="$2"; shift 2 ;;
        --self-signed)     SSL_MODE="selfsigned"; shift ;;
        --cert)            SSL_MODE="custom"; CUSTOM_CERT="$2"; shift 2 ;;
        --key)             CUSTOM_KEY="$2";   shift 2 ;;
        --no-ssl)          SSL_MODE="none";   shift ;;
        -h|--help)         usage ;;
        *)                 warn "Unknown option: $1"; usage ;;
    esac
done

if [ -z "$DOMAIN" ]; then
    warn "Domain is required: sudo $0 -d your-domain.com -e you@example.com"
    exit 1
fi

[ -z "$EMAIL" ] && EMAIL="admin@${DOMAIN}"
[ -z "$DB_PASSWORD" ] && DB_PASSWORD=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 32)

if [ "$SSL_MODE" = "custom" ]; then
    if [ -z "$CUSTOM_CERT" ] || [ -z "$CUSTOM_KEY" ]; then
        warn "--cert and --key must both be provided"
        exit 1
    fi
fi

if [ "$(id -u)" -ne 0 ]; then
    warn "Must run as root"
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════════════
# 1. System update
# ══════════════════════════════════════════════════════════════════════════════

step "1/15 — Updating system packages"
apt update && apt upgrade -y

# ══════════════════════════════════════════════════════════════════════════════
# 2. Install Node.js + pnpm
# ══════════════════════════════════════════════════════════════════════════════

step "2/15 — Installing Node.js ${NODE_VERSION} LTS + pnpm"

if ! command -v node &>/dev/null || ! node -v | grep -q "v${NODE_VERSION}"; then
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash -
    apt install -y nodejs
fi

if ! command -v pnpm &>/dev/null; then
    npm install -g pnpm@latest
fi

log "Node $(node -v), pnpm $(pnpm -v)"

# ══════════════════════════════════════════════════════════════════════════════
# 3. Install PostgreSQL
# ══════════════════════════════════════════════════════════════════════════════

step "3/15 — Setting up PostgreSQL"

apt install -y postgresql postgresql-contrib

systemctl enable postgresql
systemctl start postgresql

# Create user and database idempotently
sudo -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname = 'enumethod'" | grep -q 1 \
    || sudo -u postgres psql -c "CREATE USER enumethod WITH PASSWORD '${DB_PASSWORD}';"

sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = 'enumethod'" | grep -q 1 \
    || sudo -u postgres psql -c "CREATE DATABASE enumethod OWNER enumethod;"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE enumethod TO enumethod;" 2>/dev/null || true

log "PostgreSQL configured (user: enumethod, db: enumethod)"

# ══════════════════════════════════════════════════════════════════════════════
# 4. Install nginx, certbot, system tools
# ══════════════════════════════════════════════════════════════════════════════

step "4/15 — Installing nginx + system tools"

apt install -y \
    nginx certbot python3-certbot-nginx \
    git curl wget whois dnsutils net-tools \
    fail2ban ufw unattended-upgrades apt-listchanges \
    build-essential python3 python3-pip python3-venv

# ══════════════════════════════════════════════════════════════════════════════
# 5. Install enumeration tools
# ══════════════════════════════════════════════════════════════════════════════

step "5/15 — Installing enumeration tools"

# APT tools
apt install -y \
    nmap gobuster nikto whatweb feroxbuster ffuf \
    snmp snmp-mibs-downloader smbclient ldap-utils \
    onesixtyone rpcbind nfs-common \
    default-mysql-client postgresql-client redis-tools \
    testssl.sh jq sqlmap exploitdb \
    ssh-audit smtp-user-enum \
    2>/dev/null || true

# Pip tools
pip3 install --break-system-packages \
    enum4linux-ng sslyze crackmapexec \
    2>/dev/null || true

# Go tools (nuclei, amass)
if ! command -v go &>/dev/null; then
    GO_VERSION="1.22.0"
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz
    export PATH=$PATH:/usr/local/go/bin:/root/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin:/root/go/bin' >> /etc/profile.d/go.sh
fi

export GOPATH=/root/go
export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin

go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest 2>/dev/null || true
go install github.com/owasp-amass/amass/v4/...@master 2>/dev/null || true

# Copy Go binaries to /usr/local/bin for www-data access
cp $GOPATH/bin/* /usr/local/bin/ 2>/dev/null || true

# SecLists
if [ ! -d "/usr/share/seclists" ]; then
    apt install -y seclists 2>/dev/null || \
    git clone --depth 1 https://github.com/danielmiessler/SecLists.git /usr/share/seclists
fi

log "Enumeration tools installed"

# ══════════════════════════════════════════════════════════════════════════════
# 6. Server hardening
# ══════════════════════════════════════════════════════════════════════════════

step "6/15 — Server hardening (keeping root SSH + password auth)"

# ── Kernel hardening via sysctl ──────────────────────────────────────────────
cat > /etc/sysctl.d/99-enumethod-hardening.conf <<'SYSCTL'
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
kernel.randomize_va_space = 2
kernel.kptr_restrict = 1
SYSCTL

sysctl --system > /dev/null 2>&1
log "Kernel hardening applied"

# ── Fail2ban ─────────────────────────────────────────────────────────────────
cat > /etc/fail2ban/jail.local <<'F2B'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
maxretry = 5

[nginx-http-auth]
enabled  = true

[nginx-botsearch]
enabled  = true

[nginx-limit-req]
enabled  = true
F2B

systemctl enable fail2ban
systemctl restart fail2ban
log "Fail2ban configured"

# ── Auto security updates ───────────────────────────────────────────────────
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTOUP'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOUP

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UNATTENDED'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UNATTENDED
log "Automatic security updates enabled"

# ── Disable unnecessary services ─────────────────────────────────────────────
for svc in avahi-daemon cups bluetooth; do
    if systemctl is-enabled "$svc" 2>/dev/null | grep -q enabled; then
        systemctl disable --now "$svc" 2>/dev/null || true
        log "Disabled $svc"
    fi
done

# ── Restrictive umask ────────────────────────────────────────────────────────
if ! grep -q "^umask 027" /etc/profile; then
    echo "umask 027" >> /etc/profile
    log "Default umask set to 027"
fi

# ── Disable core dumps ──────────────────────────────────────────────────────
if ! grep -q "hard core 0" /etc/security/limits.conf 2>/dev/null; then
    echo "* hard core 0" >> /etc/security/limits.conf
    log "Core dumps disabled"
fi

# ── Harden shared memory ────────────────────────────────────────────────────
if ! grep -q '/run/shm' /etc/fstab 2>/dev/null; then
    echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0" >> /etc/fstab
    log "Shared memory hardened"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 7. Deploy application
# ══════════════════════════════════════════════════════════════════════════════

step "7/15 — Deploying application to $APP_DIR"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

if [ -d "$APP_DIR/.git" ]; then
    log "Repo exists, pulling latest"
    cd "$APP_DIR" && git pull
elif [ -f "$REPO_DIR/package.json" ] && grep -q "enumethod" "$REPO_DIR/package.json"; then
    log "Copying repo from $REPO_DIR"
    mkdir -p "$APP_DIR"
    rsync -a --exclude node_modules --exclude .next --exclude dist "$REPO_DIR/" "$APP_DIR/"
else
    warn "Cannot find source — run this from the repo or clone manually to $APP_DIR"
    exit 1
fi

cd "$APP_DIR"
chmod +x "$APP_DIR/enumerate.sh"
mkdir -p "$APP_DIR/runs"

# Install dependencies
pnpm install --frozen-lockfile 2>/dev/null || pnpm install

log "Dependencies installed"

# ══════════════════════════════════════════════════════════════════════════════
# 8. Generate .env
# ══════════════════════════════════════════════════════════════════════════════

step "8/15 — Generating .env configuration"

ENV_FILE="$APP_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    JWT_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)
    JWT_REFRESH_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)
    ENCRYPTION_SECRET=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)

    cat > "$ENV_FILE" <<ENVFILE
DATABASE_URL="postgresql://enumethod:${DB_PASSWORD}@localhost:5432/enumethod"
JWT_SECRET="${JWT_SECRET}"
JWT_REFRESH_SECRET="${JWT_REFRESH_SECRET}"
ENCRYPTION_SECRET="${ENCRYPTION_SECRET}"
NODE_ENV="production"
API_PORT=3001
FRONTEND_URL="https://${DOMAIN}"
SCRIPT_PATH="${APP_DIR}/enumerate.sh"
RUNS_DIR="${APP_DIR}/runs"
ENVFILE

    chmod 600 "$ENV_FILE"
    log "Generated .env with random secrets"
else
    log ".env already exists — skipping"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 9. Generate Prisma client, migrate, seed, and build
# ══════════════════════════════════════════════════════════════════════════════

step "9/15 — Database migrations + build"

cd "$APP_DIR"
# Source .env so DATABASE_URL is available for Prisma
set -a; source "$ENV_FILE"; set +a

pnpm exec prisma generate
pnpm exec prisma migrate deploy
pnpm exec tsx scripts/seed.ts
log "Database migrated and seeded"

# Build after Prisma client is generated
pnpm exec turbo build
log "Application built"

# ══════════════════════════════════════════════════════════════════════════════
# 10. Create systemd services
# ══════════════════════════════════════════════════════════════════════════════

step "10/15 — Creating systemd services"

cat > /etc/systemd/system/enumethod-api.service <<SERVICE
[Unit]
Description=Enumethod API (NestJS)
After=network.target postgresql.service

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$APP_DIR/apps/api
ExecStart=/usr/bin/node $APP_DIR/apps/api/dist/main.js
Restart=always
RestartSec=5
EnvironmentFile=$APP_DIR/.env
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE

cat > /etc/systemd/system/enumethod-web.service <<SERVICE
[Unit]
Description=Enumethod Web (Next.js)
After=network.target enumethod-api.service

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$APP_DIR/apps/web
ExecStart=/usr/bin/node $APP_DIR/apps/web/.next/standalone/apps/web/server.js
Restart=always
RestartSec=5
Environment="PORT=3000"
Environment="HOSTNAME=127.0.0.1"
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable enumethod-api enumethod-web
log "Systemd services created"

# ══════════════════════════════════════════════════════════════════════════════
# 11. Configure nginx
# ══════════════════════════════════════════════════════════════════════════════

step "11/15 — Configuring nginx reverse proxy"

# Remove conflicting SSL directives
sed -i 's/^\s*ssl_protocols\b/# &/'             /etc/nginx/nginx.conf
sed -i 's/^\s*ssl_prefer_server_ciphers\b/# &/' /etc/nginx/nginx.conf
sed -i 's/^\s*ssl_ciphers\b/# &/'               /etc/nginx/nginx.conf
sed -i 's/^\s*ssl_session_cache\b/# &/'          /etc/nginx/nginx.conf
sed -i 's/^\s*ssl_session_timeout\b/# &/'        /etc/nginx/nginx.conf
sed -i 's/^\s*ssl_session_tickets\b/# &/'        /etc/nginx/nginx.conf

# Global security config
cat > /etc/nginx/conf.d/security.conf <<'NGXSEC'
server_tokens off;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
NGXSEC

# Rate limiting zone
if ! grep -q "limit_req_zone.*enumethod" /etc/nginx/nginx.conf; then
    sed -i '/http {/a \    limit_req_zone $binary_remote_addr zone=enumethod_login:10m rate=5r/m;\n    limit_req_zone $binary_remote_addr zone=enumethod_api:10m rate=100r/m;' /etc/nginx/nginx.conf
fi

# Site config (initial HTTP for certbot, or full SSL)
if [ "$SSL_MODE" = "letsencrypt" ] || [ "$SSL_MODE" = "none" ]; then

cat > /etc/nginx/sites-available/enumethod <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 50M;

    # Rate limit login
    location /api/auth/login {
        limit_req zone=enumethod_login burst=3 nodelay;
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # API
    location /api/ {
        limit_req zone=enumethod_api burst=20 nodelay;
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # WebSocket
    location /ws/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400s;
    }

    # Frontend
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX

else
# selfsigned or custom — full SSL
SSL_CERT="$CUSTOM_CERT"
SSL_KEY_FILE="$CUSTOM_KEY"

if [ "$SSL_MODE" = "selfsigned" ]; then
    SSL_DIR="/etc/ssl/enumethod"
    mkdir -p "$SSL_DIR"
    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$SSL_DIR/selfsigned.key" \
        -out "$SSL_DIR/selfsigned.crt" \
        -subj "/CN=$DOMAIN" 2>/dev/null
    SSL_CERT="$SSL_DIR/selfsigned.crt"
    SSL_KEY_FILE="$SSL_DIR/selfsigned.key"
fi

cat > /etc/nginx/sites-available/enumethod <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    client_max_body_size 50M;

    ssl_certificate     $SSL_CERT;
    ssl_certificate_key $SSL_KEY_FILE;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;

    location /api/auth/login {
        limit_req zone=enumethod_login burst=3 nodelay;
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /api/ {
        limit_req zone=enumethod_api burst=20 nodelay;
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /ws/ {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400s;
    }

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX

fi

ln -sf /etc/nginx/sites-available/enumethod /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t || { warn "Nginx config error"; exit 1; }
log "Nginx configured"

# ══════════════════════════════════════════════════════════════════════════════
# 12. SSL via Let's Encrypt
# ══════════════════════════════════════════════════════════════════════════════

step "12/15 — SSL setup (mode: $SSL_MODE)"

# ══════════════════════════════════════════════════════════════════════════════
# 13. Firewall
# ══════════════════════════════════════════════════════════════════════════════

step "13/15 — Configuring firewall"

ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable
log "Firewall enabled — SSH + HTTP/HTTPS only"

# ══════════════════════════════════════════════════════════════════════════════
# 14. Sudoers
# ══════════════════════════════════════════════════════════════════════════════

step "14/15 — Configuring sudoers"

cat > /etc/sudoers.d/enumethod <<SUDOERS
$SERVICE_USER ALL=(root) NOPASSWD: $APP_DIR/enumerate.sh
SUDOERS
chmod 440 /etc/sudoers.d/enumethod
visudo -c || { warn "Sudoers syntax error"; exit 1; }
log "Sudoers configured — www-data can run enumerate.sh as root"

# ══════════════════════════════════════════════════════════════════════════════
# 15. Start services
# ══════════════════════════════════════════════════════════════════════════════

step "15/15 — Starting services"

chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"
chown root:root "$APP_DIR/enumerate.sh"
chmod 755 "$APP_DIR/enumerate.sh"

systemctl start enumethod-api
systemctl start enumethod-web
systemctl restart nginx

# Certbot after nginx is running
if [ "$SSL_MODE" = "letsencrypt" ]; then
    step "Requesting Let's Encrypt certificate"
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" \
        --redirect \
        || warn "Certbot failed — retry: certbot --nginx -d $DOMAIN"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  Deployment complete!${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo ""
if [ "$SSL_MODE" = "none" ]; then
    echo -e "  URL:      http://$DOMAIN"
else
    echo -e "  URL:      https://$DOMAIN"
fi
echo -e "  Login:    admin / TestifyThusly99@"
echo -e "            (password reset required on first login)"
echo ""
echo -e "  Services: systemctl status enumethod-api"
echo -e "            systemctl status enumethod-web"
echo -e "  Logs:     journalctl -u enumethod-api -f"
echo -e "            journalctl -u enumethod-web -f"
echo ""
echo -e "  ${BOLD}Security summary:${NC}"
echo -e "    - UFW firewall:  SSH + HTTP/HTTPS only"
echo -e "    - Fail2ban:      SSH, nginx jails active"
echo -e "    - Auto-updates:  Security patches applied automatically"
echo -e "    - Nginx:         Version hidden, security headers, rate limiting"
echo -e "    - Kernel:        SYN cookies, anti-spoofing, ASLR"
echo -e "    - JWT:           15min access + 7d rotating refresh tokens"
echo -e "    - Vault:         AES-256-GCM encrypted credential storage"
echo -e "    - SSL mode:      $SSL_MODE"
echo -e "    - Root SSH:      enabled"
echo -e "    - Password SSH:  enabled"
echo ""
echo -e "  DB Password: $DB_PASSWORD"
echo -e "  (save this — it's in $APP_DIR/.env)"
echo ""
