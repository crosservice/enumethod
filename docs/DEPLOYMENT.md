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
9. Prisma schema sync (db push) + seed
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
pnpm exec prisma db push
pnpm exec tsx scripts/seed.ts
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

---

## Legal and Ethical Use

Enumethod is a penetration testing tool. Deploying it carries legal and ethical responsibilities.

### Authorization Requirements

- **Written authorization is mandatory.** Never deploy or run scans against systems without explicit written permission from the system owner. Verbal agreements are insufficient.
- **Scope your engagement.** Authorization should specify which IP addresses, domains, and test types are permitted. Configure Enumethod's target and step options to stay within scope.
- **Retain proof of authorization.** Keep signed Rules of Engagement (RoE), statements of work, or equivalent documents for every engagement. Store them outside of Enumethod.

### Deployment Considerations

- **Restrict access.** The deploy script exposes a web interface on the public internet. Use strong passwords, change the default admin credentials immediately, and limit user accounts to authorized personnel only.
- **Network isolation.** When possible, deploy Enumethod on a network segment that only has access to authorized targets. UFW is configured to restrict inbound access, but outbound scan traffic is unrestricted by design.
- **Data sensitivity.** Scan results may contain sensitive information (credentials, vulnerabilities, internal network details). Treat the `/opt/enumethod/runs/` directory and the PostgreSQL database as confidential. Secure backups and control who has server access.
- **Credential vault.** AI provider API keys are encrypted at rest, but the encryption master key is in `.env` on the same server. Protect `.env` file permissions (the deploy script sets `chmod 600`).

### Compliance

- **Know your jurisdiction.** Unauthorized computer access is a criminal offense in most jurisdictions (e.g., CFAA in the US, Computer Misuse Act in the UK, StGB 202a-c in Germany). Penalties include fines and imprisonment.
- **Industry standards.** Follow established frameworks such as PTES (Penetration Testing Execution Standard), OWASP Testing Guide, or OSSTMM. Document your methodology and findings.
- **Data handling.** If scans reveal personal data or credentials, handle them in accordance with applicable regulations (GDPR, CCPA, HIPAA, etc.). Include data handling procedures in your Rules of Engagement.
- **Disclosure.** Follow responsible disclosure practices. Report vulnerabilities to the system owner promptly and provide adequate time for remediation before any public disclosure.
