# enumethod

Automated server enumeration toolkit implementing an 11-step attack chain for authorized penetration testing and security assessments.

`enumerate.sh` performs passive recon, port scanning, service enumeration, web analysis, credential checks, SMB/SNMP/LDAP enumeration, vulnerability scanning, and more — all in a single run against a target. Missing tools are auto-installed via apt, pip, go, or snap.

> **Legal:** Only use on systems you own or have explicit written authorization to test.

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
sudo apt install seclists
```

## Usage

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

Run all steps against a target:

```bash
sudo ./enumerate.sh 10.10.10.50
```

Run with a domain name and skip UDP scanning:

```bash
sudo ./enumerate.sh 10.10.10.50 -d example.com --skip-udp
```

Run only specific steps (port scan + web enum):

```bash
sudo ./enumerate.sh 10.10.10.50 -s 2,5
```

Route through a WireGuard VPN:

```bash
sudo ./enumerate.sh 10.10.10.50 --vpn /etc/wireguard/vpn.conf
```

Dry run to preview commands:

```bash
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

All results are saved to the output directory (`./enum_<IP>_<timestamp>/` by default), organized by step. A consolidated summary is generated in step 11.

## Reference Docs

- [enumeration.md](enumeration.md) — Full manual enumeration playbook with commands for each step
- [resources.md](resources.md) — Cybersecurity tools and learning resources
