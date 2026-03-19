# enumethod

Automated server enumeration toolkit implementing an 11-step attack chain for authorized penetration testing and security assessments.

`enumerate.sh` performs passive recon, port scanning, service enumeration, web analysis, credential checks, SMB/SNMP/LDAP enumeration, vulnerability scanning, and more — all in a single run against a target. Missing tools are auto-installed via apt, pip, go, or snap.

Includes a **web interface** for launching scans, monitoring progress in real time, viewing HTML reports, and managing past runs. Ships with a one-command deploy script for Linode/Ubuntu VPS.

> **Legal:** Only use on systems you own or have explicit written authorization to test.

## Quick Start

### CLI

```bash
git clone <repo-url> enumethod
cd enumethod
chmod +x enumerate.sh
sudo ./enumerate.sh 10.10.10.50
```

### Web App

```bash
python3 run.py
```

Creates the venv, installs dependencies, and starts the server. Open `http://localhost:5000` — login with `admin` / `TestifyThusly99@`.

### Deploy to VPS

```bash
sudo ./web/deploy.sh -d enum.example.com --letsencrypt --email you@email.com
```

See [Deployment](#deployment) for all SSL options and details.

---

## Installation

```bash
git clone <repo-url> enumethod
cd enumethod
chmod +x enumerate.sh
```

### Requirements

- **OS:** Linux (Debian/Ubuntu-based recommended — auto-install uses `apt`)
- **Root:** Must run as root or with `sudo`
- **Minimum:** `nmap` (the script auto-installs everything else it needs)
- **Recommended:** [SecLists](https://github.com/danielmiessler/SecLists) installed at `/usr/share/seclists` for wordlists

To pre-install SecLists:

```bash
sudo apt install seclists        # Kali/Parrot
sudo snap install seclists       # Ubuntu/Debian
```

---

## CLI Usage

```bash
sudo ./enumerate.sh <TARGET_IP> [OPTIONS]
```

### Options

| Flag | Description |
|------|-------------|
| `-d, --domain DOMAIN` | Domain name for passive recon (default: reverse DNS) |
| `-o, --output DIR` | Output directory (default: `./enum_<IP>_<timestamp>`) |
| `-s, --steps STEPS` | Comma-separated steps to run: `1-11` or `all` (default: `all`) |
| `-t, --timing TIMING` | Nmap timing template `0-5` (default: `4`) |
| `-w, --wordlist PATH` | Directory wordlist override |
| `--vpn CONFIG` | Route all traffic through WireGuard (path to `.conf` file) |
| `--vpn-iface NAME` | WireGuard interface name (default: `wg-enum`) |
| `--vpn-keep` | Don't tear down the VPN tunnel on exit |
| `--skip-udp` | Skip UDP scanning (saves time) |
| `--skip-bruteforce` | Skip directory/vhost brute-forcing |
| `--dry-run` | Print commands without executing |
| `-h, --help` | Show help message |

### Examples

```bash
# All steps against a target
sudo ./enumerate.sh 10.10.10.50

# With domain and skip UDP
sudo ./enumerate.sh 10.10.10.50 -d example.com --skip-udp

# Only specific steps (port scan + web enum)
sudo ./enumerate.sh 10.10.10.50 -s 2,5

# Route through WireGuard VPN
sudo ./enumerate.sh 10.10.10.50 --vpn /etc/wireguard/vpn.conf

# Dry run to preview commands
sudo ./enumerate.sh 10.10.10.50 --dry-run
```

### Enumeration Steps

| Step | Phase |
|------|-------|
| 1 | Passive Intelligence Gathering |
| 2 | Port Scanning (TCP & UDP) |
| 3 | Service Version & OS Detection |
| 4 | Web Server Enumeration |
| 5 | TLS/SSL Analysis |
| 6 | Directory & VHost Brute-Forcing |
| 7 | Authentication Service Probing |
| 8 | SMB/NetBIOS Enumeration |
| 9 | SNMP, LDAP, NFS & Mail Enumeration |
| 10 | Vulnerability Scanning |
| 11 | Results Consolidation |

### Output

All results are saved to the output directory (`./enum_<IP>_<timestamp>/` by default), organized by step. Step 11 generates:

- `report/final_summary.txt` — text summary of all findings
- `report/report.html` — full HTML report with dark-themed dashboard showing vulnerability counts, open ports, service versions, key findings, sensitive files, and output file listing

---

## Web Interface

The `web/` directory contains a Flask-based web application for running enumerations through a browser.

### Features

- **Login** — session-based authentication with bcrypt-hashed passwords
- **Dashboard** — form for target IP, domain, steps, timing, wordlist, and toggle options (skip UDP, skip brute-force, dry run). Starts the scan and streams output in real time via Server-Sent Events (SSE)
- **Progress bar** — 11-segment visual indicator showing which step is active, with live log output
- **Past runs** — table of all previous scans with status, step progress, timestamps, and links to view HTML reports
- **Report viewer** — embedded iframe rendering the generated HTML report for any completed run
- **Settings** — change the admin password (validates current password, enforces 8+ characters)

### Architecture

| File | Purpose |
|------|---------|
| `web/app.py` | Flask routes — auth, API, SSE streaming, report serving |
| `web/config.py` | Credentials, paths, step name mapping |
| `web/database.py` | SQLite schema (`runs` + `users` tables), bcrypt auth helpers |
| `web/runner.py` | Subprocess management, ANSI stripping, step detection, pub/sub for SSE |
| `web/requirements.txt` | flask, gunicorn, gevent, bcrypt |
| `web/templates/` | Jinja2 templates (login, dashboard, runs, report, settings) |
| `web/static/` | CSS (dark theme) and JS (dashboard SSE client, runs table loader) |
| `web/deploy.sh` | One-command VPS deployment script |

### Running Locally

```bash
python3 run.py
```

That's it. The launcher creates a venv, installs dependencies, and starts the server at `http://localhost:5000`. Default login: `admin` / `TestifyThusly99@`. Change the password from the Settings page after logging in.

> **Note:** `enumerate.sh` requires root. The app calls it via `sudo`, so the user running `run.py` needs passwordless sudo for the script, or you can run it as root for local testing.

---

## Deployment

`web/deploy.sh` deploys the full stack to an Ubuntu 24.04 LTS VPS (tested on Linode).

### Usage

```bash
sudo ./web/deploy.sh -d <DOMAIN> [OPTIONS]
```

### Options

| Flag | Description |
|------|-------------|
| `-d, --domain DOMAIN` | **(Required)** FQDN for nginx and SSL |
| `--letsencrypt` | Use Let's Encrypt via Certbot (default) |
| `--email EMAIL` | Email for Let's Encrypt (default: `admin@DOMAIN`) |
| `--self-signed` | Generate a self-signed certificate |
| `--cert FILE --key FILE` | Use your own SSL certificate and private key |
| `--no-ssl` | HTTP only, no SSL |
| `--port PORT` | Gunicorn bind port (default: `5000`) |
| `-h, --help` | Show help |

### SSL Examples

```bash
# Let's Encrypt (default, recommended for production)
sudo ./web/deploy.sh -d enum.example.com --email admin@example.com

# Self-signed (quick setup, internal use)
sudo ./web/deploy.sh -d enum.example.com --self-signed

# Custom certificate
sudo ./web/deploy.sh -d enum.example.com --cert /path/to/cert.pem --key /path/to/key.pem

# No SSL (HTTP only)
sudo ./web/deploy.sh -d enum.example.com --no-ssl
```

### What the Deploy Script Does

1. **System update** — `apt update && apt upgrade`
2. **Dependencies** — Python 3, nginx, certbot, nmap, fail2ban, UFW, unattended-upgrades, build tools
3. **Server hardening** (see [Security Hardening](#security-hardening))
4. **App deployment** — copies repo to `/opt/enumethod/`
5. **Python venv** — creates virtualenv, installs pip requirements
6. **File permissions** — `www-data` owns the app, root owns `enumerate.sh`
7. **Sudoers** — scoped `NOPASSWD` entry so `www-data` can only run `enumerate.sh` as root
8. **Systemd service** — gunicorn with gevent workers, auto-restart, no timeout
9. **SSL** — configured per the chosen mode
10. **Nginx** — reverse proxy with SSE support (buffering disabled), security headers, rate limiting on `/login`
11. **Firewall** — UFW with default deny inbound, allows only SSH + HTTP/HTTPS

### Post-Deploy

```bash
# Check service status
systemctl status enumethod

# View logs
journalctl -u enumethod -f
tail -f /var/log/enumethod-*.log

# Check fail2ban
fail2ban-client status

# Install additional enum tools
apt install -y gobuster nikto whatweb enum4linux snmp snmp-mibs-downloader
pip install impacket
```

---

## Security Hardening

The deploy script applies the following hardening measures. Root SSH and password SSH are **kept enabled**.

### Firewall (UFW)

- Default deny all inbound traffic
- Allow only SSH (22) and HTTP/HTTPS (80/443)

### Fail2ban

- SSH brute-force protection (5 attempts, 1 hour ban)
- Nginx HTTP auth jail
- Nginx bot search jail
- Nginx rate limit jail

### Nginx

- Server version hidden (`server_tokens off`)
- Security headers: `X-Frame-Options`, `X-Content-Type-Options`, `X-XSS-Protection`, `Referrer-Policy`, `Permissions-Policy`
- TLS 1.2 and 1.3 only with strong cipher suites
- HSTS enabled (when SSL is active)
- Rate limiting on `/login` (10 req/s with burst of 5)

### Kernel (sysctl)

- SYN flood protection (TCP syncookies)
- Reverse path filtering (anti-spoofing)
- ICMP redirect rejection
- Source-routed packet rejection
- ICMP broadcast and bogus error response rejection
- Martian packet logging
- IP forwarding disabled
- Full ASLR (`randomize_va_space = 2`)
- Kernel pointer restriction

### Automatic Updates

- Unattended security upgrades enabled
- Weekly auto-clean of old packages
- No automatic reboot

### Other

- Core dumps disabled
- Shared memory mounted with `noexec,nosuid`
- Default umask set to `027`
- Unnecessary services disabled (avahi, cups, bluetooth)
- Web app directory restricted (`chmod 700`)

---

## Project Structure

```
enumethod/
  run.py                # Single-command launcher (venv + deps + server)
  enumerate.sh          # Main enumeration script (11-step chain)
  enumeration.md        # Manual enumeration playbook with commands
  resources.md          # Curated cybersecurity tool and resource list
  runs/                 # Scan output directories (created at runtime)
  web/
    app.py              # Flask application
    config.py           # Configuration constants
    database.py         # SQLite + bcrypt auth
    runner.py           # Subprocess + SSE streaming
    requirements.txt    # Python dependencies
    deploy.sh           # VPS deployment script
    templates/          # Jinja2 HTML templates
      base.html         # Shared layout with nav
      login.html        # Login page
      dashboard.html    # Scan form + live progress
      runs.html         # Past runs table
      report.html       # Report iframe viewer
      settings.html     # Password change form
    static/
      css/style.css     # Dark theme styles
      js/dashboard.js   # SSE client + progress bar
      js/runs.js        # Past runs table loader
```

## Reference Docs

- [enumeration.md](enumeration.md) — Full manual enumeration playbook with commands for each step
- [resources.md](resources.md) — Curated cybersecurity tools and resources
