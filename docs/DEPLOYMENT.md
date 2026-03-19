# Enumethod Deployment Guide

## Prerequisites

- Fresh Ubuntu 24.04 LTS server (Linode recommended)
- Domain name pointed to the server's IP
- Root SSH access

## Quick Deploy

```bash
# Clone the repo
git clone <your-repo-url> /opt/enumethod
cd /opt/enumethod

# Run the deploy script
sudo ./scripts/deploy.sh -d enum.example.com -e you@example.com
```

## Deploy Script Options

```
sudo ./scripts/deploy.sh -d <DOMAIN> -e <EMAIL> [OPTIONS]

Required:
  -d, --domain DOMAIN         FQDN for nginx + SSL
  -e, --email EMAIL           Email for Let's Encrypt

Optional:
  --db-password PW            PostgreSQL password (default: random)
  --node-version VER          Node.js major version (default: 22)
  --self-signed               Use self-signed SSL instead of Let's Encrypt
  --cert FILE --key FILE      Use custom certificate
  --no-ssl                    HTTP only, no SSL
```

## What the Deploy Script Does

1. System update
2. Install Node.js 22 LTS + pnpm
3. Install PostgreSQL + create DB/user
4. Install nginx, certbot, system tools
5. Install enumeration tools (nmap, gobuster, nikto, nuclei, amass, etc.)
6. Server hardening (kernel, fail2ban, auto-updates, core dumps, umask)
7. Deploy application (copy/build)
8. Generate .env with random secrets
9. Run Prisma migrations + seed
10. Create systemd services
11. Configure nginx reverse proxy with rate limiting
12. SSL via Let's Encrypt (or alternatives)
13. UFW firewall (SSH + HTTP/HTTPS only)
14. Sudoers (www-data can run enumerate.sh as root)
15. Start services

## Post-Deployment

### First Login

- URL: `https://your-domain.com`
- Username: `admin`
- Password: `TestifyThusly99@`
- You will be forced to change the password on first login

### Service Management

```bash
# Check status
systemctl status enumethod-api
systemctl status enumethod-web

# View logs
journalctl -u enumethod-api -f
journalctl -u enumethod-web -f

# Restart
systemctl restart enumethod-api
systemctl restart enumethod-web
```

### Updating

```bash
cd /opt/enumethod
sudo ./scripts/rebuild.sh
```

This pulls latest code, installs deps, runs migrations, rebuilds, and restarts services.

## Security Overview

| Feature | Details |
| ------- | ------- |
| Firewall | UFW: SSH + HTTP/HTTPS only |
| Fail2ban | SSH, nginx-http-auth, nginx-limit-req jails |
| Auto-updates | Security patches applied automatically |
| Nginx | Version hidden, HSTS, security headers, rate limiting |
| Kernel | SYN cookies, anti-spoofing, ASLR, no ICMP redirects |
| Auth | JWT with 15min access + 7d rotating refresh tokens |
| Vault | AES-256-GCM encrypted API key storage |
| Root SSH | Enabled (by design for pentest servers) |

## Environment Variables

All stored in `/opt/enumethod/.env`:

| Variable | Description |
| -------- | ----------- |
| DATABASE_URL | PostgreSQL connection string |
| JWT_SECRET | Secret for access token signing |
| JWT_REFRESH_SECRET | Secret for refresh token signing |
| ENCRYPTION_SECRET | Master key for credential vault |
| API_PORT | Backend port (default: 3001) |
| FRONTEND_URL | Frontend URL for CORS |
| SCRIPT_PATH | Path to enumerate.sh |
| RUNS_DIR | Directory for scan output |

## Troubleshooting

### Services won't start
```bash
journalctl -u enumethod-api --no-pager -n 50
journalctl -u enumethod-web --no-pager -n 50
```

### Database issues
```bash
cd /opt/enumethod
sudo -u www-data pnpm exec prisma migrate status
sudo -u www-data pnpm exec prisma migrate deploy
```

### Nginx issues
```bash
nginx -t
systemctl restart nginx
cat /var/log/nginx/error.log
```

### SSL renewal
Certbot auto-renews via systemd timer. Manual renewal:
```bash
certbot renew --nginx
```
