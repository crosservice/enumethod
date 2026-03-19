#!/usr/bin/env bash
# ==============================================================================
# deploy.sh — Deploy enumethod web app on a Linode VPS (Ubuntu 24.04 LTS)
#
# Usage:
#   sudo ./deploy.sh -d <DOMAIN> [OPTIONS]
#
# Required:
#   -d, --domain DOMAIN       FQDN for nginx + SSL (e.g., enum.example.com)
#
# SSL options (pick one):
#   --letsencrypt             Use Let's Encrypt / Certbot (default)
#   --email EMAIL             Email for Let's Encrypt (default: admin@DOMAIN)
#   --self-signed             Generate a self-signed certificate instead
#   --cert FILE --key FILE    Use your own certificate and private key
#   --no-ssl                  HTTP only, no SSL
#
# Other:
#   --port PORT               Gunicorn bind port (default: 5000)
#   -h, --help                Show this help
#
# Run as root on a fresh Ubuntu 24.04 Linode instance.
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
SSL_MODE="letsencrypt"
CUSTOM_CERT=""
CUSTOM_KEY=""
BIND_PORT=5000
APP_DIR="/opt/enumethod"
WEB_DIR="$APP_DIR/web"
VENV_DIR="$WEB_DIR/venv"
SERVICE_USER="www-data"

usage() {
    sed -n '2,/^# =====/{ /^# =====/d; s/^# \?//; p }' "$0"
    exit 0
}

# ── Parse args ───────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--domain)       DOMAIN="$2";       shift 2 ;;
        --email)           EMAIL="$2";        shift 2 ;;
        --letsencrypt)     SSL_MODE="letsencrypt"; shift ;;
        --self-signed)     SSL_MODE="selfsigned";  shift ;;
        --cert)            SSL_MODE="custom"; CUSTOM_CERT="$2"; shift 2 ;;
        --key)             CUSTOM_KEY="$2";   shift 2 ;;
        --no-ssl)          SSL_MODE="none";   shift ;;
        --port)            BIND_PORT="$2";    shift 2 ;;
        -h|--help)         usage ;;
        *)                 warn "Unknown option: $1"; usage ;;
    esac
done

if [ -z "$DOMAIN" ]; then
    warn "Domain is required: sudo $0 -d your-domain.com"
    exit 1
fi

[ -z "$EMAIL" ] && EMAIL="admin@${DOMAIN}"

if [ "$SSL_MODE" = "custom" ]; then
    if [ -z "$CUSTOM_CERT" ] || [ -z "$CUSTOM_KEY" ]; then
        warn "--cert and --key must both be provided"
        exit 1
    fi
    [ ! -f "$CUSTOM_CERT" ] && { warn "Cert file not found: $CUSTOM_CERT"; exit 1; }
    [ ! -f "$CUSTOM_KEY" ]  && { warn "Key file not found: $CUSTOM_KEY"; exit 1; }
fi

if [ "$(id -u)" -ne 0 ]; then
    warn "Must run as root"
    exit 1
fi

# ══════════════════════════════════════════════════════════════════════════════
# 1. System update
# ══════════════════════════════════════════════════════════════════════════════

step "Updating system packages"
apt update && apt upgrade -y

# ══════════════════════════════════════════════════════════════════════════════
# 2. Install dependencies
# ══════════════════════════════════════════════════════════════════════════════

step "Installing dependencies"
apt install -y \
    python3 python3-pip python3-venv python3-dev \
    nginx certbot python3-certbot-nginx \
    git nmap curl wget whois dnsutils net-tools \
    fail2ban ufw unattended-upgrades apt-listchanges \
    libffi-dev build-essential

# ══════════════════════════════════════════════════════════════════════════════
# 3. Server hardening
# ══════════════════════════════════════════════════════════════════════════════

step "Hardening server (keeping root SSH + password auth enabled)"

# ── Kernel / network hardening via sysctl ────────────────────────────────────
cat > /etc/sysctl.d/99-enumethod-hardening.conf <<'SYSCTL'
# Ignore ICMP redirects (MITM protection)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Ignore source-routed packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Enable SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# Log martian packets
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Enable reverse path filtering (anti-spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable IP forwarding (not a router)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Harden kernel
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

# ── Automatic security updates ───────────────────────────────────────────────
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

# ── Restrict /tmp and /var/tmp ───────────────────────────────────────────────
if ! grep -q '/tmp' /etc/fstab 2>/dev/null; then
    log "Consider mounting /tmp with noexec,nosuid,nodev for additional hardening"
fi

# ── Disable unnecessary services ─────────────────────────────────────────────
for svc in avahi-daemon cups bluetooth; do
    if systemctl is-enabled "$svc" 2>/dev/null | grep -q enabled; then
        systemctl disable --now "$svc" 2>/dev/null || true
        log "Disabled $svc"
    fi
done

# ── Set restrictive default umask ────────────────────────────────────────────
if ! grep -q "^umask 027" /etc/profile; then
    echo "umask 027" >> /etc/profile
    log "Default umask set to 027"
fi

# ── Limit core dumps ────────────────────────────────────────────────────────
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
# 4. Deploy app
# ══════════════════════════════════════════════════════════════════════════════

step "Deploying application to $APP_DIR"
if [ -d "$APP_DIR/.git" ]; then
    log "Repo exists, pulling latest"
    cd "$APP_DIR" && git pull
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    REPO_DIR="$(dirname "$SCRIPT_DIR")"

    if [ -f "$REPO_DIR/enumerate.sh" ]; then
        log "Copying repo from $REPO_DIR"
        mkdir -p "$APP_DIR"
        cp -r "$REPO_DIR"/* "$APP_DIR/"
        cp -r "$REPO_DIR"/.git "$APP_DIR/" 2>/dev/null || true
    else
        warn "Cannot find enumerate.sh — run this from the repo or clone manually to $APP_DIR"
        exit 1
    fi
fi

chmod +x "$APP_DIR/enumerate.sh"
mkdir -p "$APP_DIR/runs"

# ══════════════════════════════════════════════════════════════════════════════
# 5. Python venv
# ══════════════════════════════════════════════════════════════════════════════

step "Setting up Python virtual environment"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install -r "$WEB_DIR/requirements.txt"

# ══════════════════════════════════════════════════════════════════════════════
# 6. File ownership
# ══════════════════════════════════════════════════════════════════════════════

step "Setting file ownership"
chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"
chown root:root "$APP_DIR/enumerate.sh"
chmod 755 "$APP_DIR/enumerate.sh"
# Protect the database
chmod 700 "$WEB_DIR"

# ══════════════════════════════════════════════════════════════════════════════
# 7. Sudoers
# ══════════════════════════════════════════════════════════════════════════════

step "Configuring sudoers for enumerate.sh"
cat > /etc/sudoers.d/enumethod <<SUDOERS
$SERVICE_USER ALL=(root) NOPASSWD: $APP_DIR/enumerate.sh
SUDOERS
chmod 440 /etc/sudoers.d/enumethod
visudo -c || { warn "Sudoers syntax error"; exit 1; }
log "Sudoers configured"

# ══════════════════════════════════════════════════════════════════════════════
# 8. Systemd service
# ══════════════════════════════════════════════════════════════════════════════

step "Creating systemd service"
cat > /etc/systemd/system/enumethod.service <<SERVICE
[Unit]
Description=enumethod web application
After=network.target

[Service]
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$WEB_DIR
ExecStart=$VENV_DIR/bin/gunicorn \\
    --worker-class gevent \\
    --workers 2 \\
    --bind 127.0.0.1:${BIND_PORT} \\
    --timeout 0 \\
    --access-logfile /var/log/enumethod-access.log \\
    --error-logfile /var/log/enumethod-error.log \\
    app:app
Restart=always
RestartSec=5
# Hardening
NoNewPrivileges=false
ProtectSystem=false
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable enumethod
log "Service created"

# ══════════════════════════════════════════════════════════════════════════════
# 9. SSL setup
# ══════════════════════════════════════════════════════════════════════════════

step "Setting up SSL (mode: $SSL_MODE)"

SSL_CERT=""
SSL_KEY=""

case "$SSL_MODE" in
    selfsigned)
        SSL_DIR="/etc/ssl/enumethod"
        mkdir -p "$SSL_DIR"
        openssl req -x509 -nodes -days 365 \
            -newkey rsa:2048 \
            -keyout "$SSL_DIR/selfsigned.key" \
            -out "$SSL_DIR/selfsigned.crt" \
            -subj "/CN=$DOMAIN" \
            2>/dev/null
        SSL_CERT="$SSL_DIR/selfsigned.crt"
        SSL_KEY="$SSL_DIR/selfsigned.key"
        log "Self-signed certificate generated"
        ;;
    custom)
        SSL_CERT="$CUSTOM_CERT"
        SSL_KEY="$CUSTOM_KEY"
        log "Using custom certificate"
        ;;
    none)
        log "Skipping SSL — HTTP only"
        ;;
    letsencrypt)
        log "Certbot will run after nginx starts"
        ;;
esac

# ══════════════════════════════════════════════════════════════════════════════
# 10. Nginx
# ══════════════════════════════════════════════════════════════════════════════

step "Configuring nginx"

# Remove default SSL directives from nginx.conf to avoid duplicates
sed -i 's/^\s*ssl_protocols\b/# &/'             /etc/nginx/nginx.conf
sed -i 's/^\s*ssl_prefer_server_ciphers\b/# &/' /etc/nginx/nginx.conf
sed -i 's/^\s*ssl_ciphers\b/# &/'               /etc/nginx/nginx.conf
sed -i 's/^\s*ssl_session_cache\b/# &/'          /etc/nginx/nginx.conf
sed -i 's/^\s*ssl_session_timeout\b/# &/'        /etc/nginx/nginx.conf
sed -i 's/^\s*ssl_session_tickets\b/# &/'        /etc/nginx/nginx.conf

# Harden nginx globally
cat > /etc/nginx/conf.d/security.conf <<'NGXSEC'
# Hide nginx version
server_tokens off;

# Security headers
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

# SSL hardening
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
NGXSEC

# Rate limiting zone
if ! grep -q "limit_req_zone" /etc/nginx/nginx.conf; then
    sed -i '/http {/a \    limit_req_zone $binary_remote_addr zone=enumethod_limit:10m rate=10r/s;' /etc/nginx/nginx.conf
fi

# Build site config based on SSL mode
if [ "$SSL_MODE" = "none" ]; then

cat > /etc/nginx/sites-available/enumethod <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 10M;

    # Rate limiting on login
    location /login {
        limit_req zone=enumethod_limit burst=5 nodelay;
        proxy_pass http://127.0.0.1:${BIND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        proxy_pass http://127.0.0.1:${BIND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ ^/api/runs/\d+/stream\$ {
        proxy_pass http://127.0.0.1:${BIND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding off;
        proxy_read_timeout 86400s;
    }
}
NGINX

elif [ "$SSL_MODE" = "letsencrypt" ]; then

# Minimal config for certbot to work — certbot rewrites it with SSL
cat > /etc/nginx/sites-available/enumethod <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    client_max_body_size 10M;

    location /login {
        limit_req zone=enumethod_limit burst=5 nodelay;
        proxy_pass http://127.0.0.1:${BIND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        proxy_pass http://127.0.0.1:${BIND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ ^/api/runs/\d+/stream\$ {
        proxy_pass http://127.0.0.1:${BIND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding off;
        proxy_read_timeout 86400s;
    }
}
NGINX

else
# selfsigned or custom — write full SSL config
cat > /etc/nginx/sites-available/enumethod <<NGINX
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    client_max_body_size 10M;

    ssl_certificate     $SSL_CERT;
    ssl_certificate_key $SSL_KEY;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains" always;

    location /login {
        limit_req zone=enumethod_limit burst=5 nodelay;
        proxy_pass http://127.0.0.1:${BIND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / {
        proxy_pass http://127.0.0.1:${BIND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ ^/api/runs/\d+/stream\$ {
        proxy_pass http://127.0.0.1:${BIND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Connection '';
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding off;
        proxy_read_timeout 86400s;
    }
}
NGINX

fi

ln -sf /etc/nginx/sites-available/enumethod /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t || { warn "Nginx config error"; exit 1; }
log "Nginx configured"

# ══════════════════════════════════════════════════════════════════════════════
# 11. Start services
# ══════════════════════════════════════════════════════════════════════════════

step "Starting services"
systemctl start enumethod
systemctl restart nginx
log "Services running"

# ── Certbot (after nginx is running) ─────────────────────────────────────────
if [ "$SSL_MODE" = "letsencrypt" ]; then
    step "Requesting Let's Encrypt certificate"
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --email "$EMAIL" \
        --redirect \
        || warn "Certbot failed — SSL not configured. Retry: certbot --nginx -d $DOMAIN"
fi

# ══════════════════════════════════════════════════════════════════════════════
# 12. Firewall
# ══════════════════════════════════════════════════════════════════════════════

step "Configuring firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable
log "Firewall enabled — only SSH + HTTP/HTTPS allowed, all other inbound denied"

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
echo -e "  Login:    admin"
echo -e ""
echo -e "  Service:  systemctl status enumethod"
echo -e "  Logs:     journalctl -u enumethod -f"
echo -e "            tail -f /var/log/enumethod-*.log"
echo -e "  Fail2ban: fail2ban-client status"
echo ""
echo -e "  ${BOLD}Security summary:${NC}"
echo -e "    - UFW firewall:  SSH + HTTP/HTTPS only (all other inbound denied)"
echo -e "    - Fail2ban:      SSH, nginx auth, bot search, rate limit jails active"
echo -e "    - Auto-updates:  Security patches applied automatically"
echo -e "    - Nginx:         Version hidden, security headers, rate limiting on /login"
echo -e "    - Kernel:        SYN cookies, anti-spoofing, ASLR, no ICMP redirects"
echo -e "    - SSL mode:      $SSL_MODE"
echo -e "    - Root SSH:      enabled"
echo -e "    - Password SSH:  enabled"
echo ""
echo -e "  To install enumeration tools (nmap is already installed):"
echo -e "    apt install -y gobuster nikto whatweb enum4linux snmp snmp-mibs-downloader"
echo -e "    pip install impacket"
echo -e "    # See resources.md for the full list"
echo ""
