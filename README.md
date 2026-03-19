# enumethod

Automated server enumeration toolkit implementing an 11-step attack chain for authorized penetration testing and security assessments.

`enumerate.sh` performs passive recon, port scanning, service enumeration, web analysis, credential checks, SMB/SNMP/LDAP enumeration, vulnerability scanning, and more — all in a single run against a target. Missing tools are auto-installed via apt, pip, go, or snap.

**v2** features a full-stack web interface with real-time WebSocket streaming, role-based access control, pause/resume/cancel, AI-powered security assessments, an encrypted credential vault, searchable reports, and single-command deployment.

> **Legal:** Only use on systems you own or have explicit written authorization to test.

## Quick Start

### CLI

```bash
git clone <repo-url> enumethod
cd enumethod
chmod +x enumerate.sh
sudo ./enumerate.sh 10.10.10.50
```

### Web App (local development)

```bash
pnpm install
cp .env.example .env    # edit DATABASE_URL with your PostgreSQL connection
pnpm exec prisma generate
pnpm exec prisma db push
pnpm exec tsx scripts/seed.ts
pnpm dev
```

Open `http://localhost:3000` — login with `admin` / `TestifyThusly99@` (password reset required on first login).

### Deploy to VPS

```bash
sudo ./scripts/deploy.sh -d enum.example.com -e you@example.com
```

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for all options and details.

---

## Stack

| Layer      | Technology                              |
| ---------- | --------------------------------------- |
| Frontend   | Next.js 14 (App Router) + Tailwind CSS  |
| Backend    | Nest.js + Prisma ORM                    |
| Database   | PostgreSQL                               |
| Real-time  | Socket.IO (WebSocket)                    |
| Auth       | JWT (access 15min + refresh 7d, rotation)|
| Encryption | AES-256-GCM (credential vault)           |
| AI         | Claude / OpenAI + NVD CVE enrichment    |
| Deploy     | Ubuntu 24.04 + nginx + systemd           |
| Monorepo   | pnpm workspaces + Turborepo              |

---

## Web Interface Features

- **Dashboard** — scan form with target IP, domain, steps, timing, wordlists, and toggles. Real-time output streaming via WebSocket with 11-segment step progress bar
- **Pause / Resume / Cancel** — control running scans mid-execution
- **Past Runs** — paginated table with status badges, links to reports and ZIP exports
- **Run Detail** — tabbed view with searchable per-command output, embedded HTML report, and AI assessment
- **AI Assessment** — Claude or OpenAI analyzes scan results with CVE enrichment from the NVD database. Configurable prompt template with severity summary
- **User Management** — role-based access (admin / view), forced password reset on first login
- **Credential Vault** — AES-256-GCM encrypted API key storage for AI providers
- **Settings** — password change, AI prompt template editor

---

## CLI Usage

```bash
sudo ./enumerate.sh <TARGET_IP> [OPTIONS]
```

| Flag | Description |
|------|-------------|
| `-d, --domain DOMAIN` | Domain name for passive recon (default: reverse DNS) |
| `-o, --output DIR` | Output directory (default: `./enum_<IP>_<timestamp>`) |
| `-s, --steps STEPS` | Comma-separated steps: `1-11` or `all` (default: `all`) |
| `-t, --timing TIMING` | Nmap timing template `0-5` (default: `4`) |
| `-w, --wordlist PATH` | Directory wordlist override |
| `--vpn CONFIG` | Route traffic through WireGuard (path to `.conf` file) |
| `--skip-udp` | Skip UDP scanning (saves time) |
| `--skip-bruteforce` | Skip directory/vhost brute-forcing |
| `--dry-run` | Print commands without executing |

### Enumeration Steps

| Step | Phase |
|------|-------|
| 1 | Passive Recon & OSINT |
| 2 | Active Host Discovery |
| 3 | Port Scanning & Service Enumeration |
| 4 | Web Stack Fingerprinting |
| 5 | Vulnerability Scanning |
| 6 | Authentication Testing |
| 7 | SMB / NetBIOS / RPC |
| 8 | SNMP Enumeration |
| 9 | LDAP / NFS / Databases |
| 10 | Directory & VHost Brute-forcing |
| 11 | Report Generation |

---

## Deployment

`scripts/deploy.sh` deploys the full stack to an Ubuntu 24.04 LTS server (tested on Linode).

```bash
sudo ./scripts/deploy.sh -d <DOMAIN> -e <EMAIL> [OPTIONS]
```

| Flag | Description |
|------|-------------|
| `-d, --domain DOMAIN` | **(Required)** FQDN for nginx and SSL |
| `-e, --email EMAIL` | Email for Let's Encrypt |
| `--db-password PW` | PostgreSQL password (default: random) |
| `--node-version VER` | Node.js major version (default: 22) |
| `--self-signed` | Use self-signed certificate |
| `--cert FILE --key FILE` | Use custom SSL certificate |
| `--no-ssl` | HTTP only, no SSL |

The deploy script handles everything: Node.js, pnpm, PostgreSQL, nginx, SSL, 30+ enumeration tools, kernel hardening, fail2ban, firewall, systemd services, and database seeding.

### Updating

```bash
cd /opt/enumethod
sudo ./scripts/rebuild.sh
```

---

## Security

- JWT access tokens (15min) + rotating refresh tokens (7d) with bcrypt-hashed storage
- AES-256-GCM credential encryption with PBKDF2-derived key
- Helmet HTTP security headers + CORS restricted to frontend origin
- Input validation via class-validator (whitelist + forbidNonWhitelisted)
- Rate limiting: 5/min on login, 100/min global (Nest ThrottlerModule + nginx)
- nginx: version hidden, HSTS, security headers, rate limiting
- Fail2ban jails: sshd, nginx-http-auth, nginx-limit-req
- UFW firewall: SSH + HTTP/HTTPS only
- Kernel hardening: SYN cookies, anti-spoofing, ASLR, no ICMP redirects
- Root SSH and password SSH remain enabled (by design for pentest servers)

---

## Project Structure

```
enumethod/
  enumerate.sh               # 11-step enumeration script
  enumeration.md             # Manual enumeration playbook
  resources.md               # Curated cybersecurity tools and resources
  package.json               # pnpm workspace root
  pnpm-workspace.yaml
  turbo.json
  prisma/
    schema.prisma            # Database schema (PostgreSQL)
  apps/
    api/                     # Nest.js backend
      src/
        auth/                # JWT login/refresh/logout, Passport strategy
        users/               # CRUD (admin only) + self-service password change
        runs/                # CRUD + RunManager + WebSocket gateway
        reports/             # HTML report serving + ZIP export
        credentials/         # AES-256-GCM vault + CryptoService
        ai/                  # Claude/OpenAI providers, CVE enrichment
        settings/            # Key-value settings CRUD
        common/              # Guards, decorators, filters, pipes
    web/                     # Next.js frontend
      src/
        app/
          login/             # Login page
          (authenticated)/   # Auth-guarded layout
            dashboard/       # Scan form + live output + step bar
            runs/            # Past runs table + run detail
            settings/        # Password change + AI prompt editor
            admin/           # User management + credential vault
        components/          # StepBar, LogOutput, ScanForm
        hooks/               # useWebSocket, useApi
        lib/                 # Auth context, API client, constants
  packages/
    shared/                  # Shared TypeScript types + constants
  scripts/
    deploy.sh                # Full idempotent VPS deployment
    rebuild.sh               # Pull, build, migrate, restart
    seed.ts                  # Database seeding
  docs/
    ARCHITECTURE.md
    API.md
    DEPLOYMENT.md
    USAGE.md
  previous_versions/
    v1/                      # Legacy Flask/SQLite web app
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — System design, data flow, WebSocket protocol
- [docs/API.md](docs/API.md) — Full REST API reference
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — VPS deployment guide and troubleshooting
- [docs/USAGE.md](docs/USAGE.md) — User guide for the web interface
- [enumeration.md](enumeration.md) — Manual enumeration playbook with commands
- [resources.md](resources.md) — Curated cybersecurity tools and resources
