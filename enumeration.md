# Server Enumeration Methodology

A structured approach to identifying vulnerabilities on servers you own or have explicit authorization to test.

---

## Phase 1: Passive Reconnaissance

Gather information without directly interacting with the target.

### DNS Enumeration

- **Tools:** `dig`, `host`, `nslookup`, `dnsenum`, `dnsrecon`, `amass`
- Enumerate subdomains, MX records, NS records, TXT records (SPF/DKIM/DMARC), zone transfers
- Check for dangling DNS records pointing to decommissioned services

```bash
dig any example.com
dig axfr example.com @ns1.example.com   # zone transfer attempt
amass enum -d example.com
dnsrecon -d example.com -t std
```

### WHOIS and Certificate Transparency

- **Tools:** `whois`, crt.sh, Censys, Shodan
- Identify registered domains, IP ranges, and alternative names from TLS certificates

### OSINT

- Search for exposed credentials in public repos (`trufflehog`, `gitleaks`)
- Review historical snapshots via Wayback Machine
- Check paste sites and breach databases for leaked credentials tied to your domain

---

## Phase 2: Active Host Discovery

### Network Scanning

- **Tools:** `nmap`, `masscan`, `arp-scan`

```bash
# Host discovery on a subnet
nmap -sn 192.168.1.0/24

# Fast SYN scan of all ports
nmap -sS -p- --min-rate 5000 -oA full_syn TARGET

# Top 1000 ports with version detection
nmap -sV -sC -oA default_scan TARGET

# UDP scan (top 100 ports, UDP is slow)
nmap -sU --top-ports 100 -oA udp_scan TARGET
```

### Key nmap Options

| Flag | Purpose |
|------|---------|
| `-sV` | Service/version detection |
| `-sC` | Default NSE scripts |
| `-O` | OS fingerprinting |
| `-A` | Aggressive (OS + version + scripts + traceroute) |
| `--script vuln` | Run vulnerability-detection scripts |
| `-oA` | Output in all formats (for later analysis) |

---

## Phase 3: Service Enumeration

For each open port/service discovered, enumerate further.

### Web Services (80/443)

- **Tools:** `nikto`, `gobuster`, `feroxbuster`, `ffuf`, `whatweb`, `wappalyzer`, `burpsuite`

```bash
# Technology fingerprinting
whatweb https://TARGET

# Directory and file brute-forcing
gobuster dir -u https://TARGET -w /usr/share/wordlists/dirb/common.txt -x php,html,txt,bak
feroxbuster -u https://TARGET -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt

# Virtual host enumeration
ffuf -u https://TARGET -H "Host: FUZZ.example.com" -w subdomains.txt -fc 301,302

# Vulnerability scanning
nikto -h https://TARGET
```

- Check for exposed admin panels, backup files, `.git`/`.env` disclosure
- Review TLS configuration with `testssl.sh` or `sslyze`
- Inspect HTTP headers (HSTS, CSP, X-Frame-Options, etc.)

### SSH (22)

- **Tools:** `ssh-audit`, `nmap`

```bash
ssh-audit TARGET
nmap --script ssh2-enum-algos,ssh-auth-methods -p 22 TARGET
```

- Check for weak key exchange algorithms, ciphers, or MACs
- Confirm password authentication is disabled if key-only is intended

### SMB (139/445)

- **Tools:** `enum4linux-ng`, `smbclient`, `crackmapexec`, `nmap`

```bash
enum4linux-ng -A TARGET
smbclient -L //TARGET -N
crackmapexec smb TARGET --shares
nmap --script smb-enum-shares,smb-enum-users,smb-vuln* -p 445 TARGET
```

- Check for null sessions, anonymous share access, SMBv1 (EternalBlue)

### DNS (53)

```bash
nmap --script dns-zone-transfer,dns-brute -p 53 TARGET
```

### SMTP (25/465/587)

- **Tools:** `smtp-user-enum`, `nmap`

```bash
smtp-user-enum -M VRFY -U users.txt -t TARGET
nmap --script smtp-enum-users,smtp-open-relay -p 25 TARGET
```

- Test for open relay, user enumeration via VRFY/EXPN/RCPT TO

### SNMP (161/UDP)

- **Tools:** `snmpwalk`, `onesixtyone`, `snmp-check`

```bash
onesixtyone -c /usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt TARGET
snmpwalk -v2c -c public TARGET
```

### Databases

| Service | Port | Tools |
|---------|------|-------|
| MySQL | 3306 | `mysql`, `nmap --script mysql-*` |
| PostgreSQL | 5432 | `psql`, `nmap --script pgsql-brute` |
| MSSQL | 1433 | `sqsh`, `crackmapexec mssql`, `nmap --script ms-sql-*` |
| Redis | 6379 | `redis-cli`, `nmap --script redis-info` |
| MongoDB | 27017 | `mongosh`, `nmap --script mongodb-*` |

- Check for unauthenticated access, default credentials, version-specific CVEs

### RPC / NFS (111/2049)

```bash
rpcinfo -p TARGET
showmount -e TARGET
nmap --script nfs-ls,nfs-showmount -p 111,2049 TARGET
```

### LDAP (389/636)

```bash
ldapsearch -x -H ldap://TARGET -b "dc=example,dc=com"
nmap --script ldap-rootdse,ldap-search -p 389 TARGET
```

---

## Phase 4: Vulnerability Identification

### Automated Scanning

- **Tools:** `OpenVAS` (Greenbone), `Nessus`, `Nuclei`, `Trivy`

```bash
# Nuclei — template-based scanner
nuclei -u https://TARGET -t cves/ -t misconfigurations/
nuclei -l urls.txt -t /path/to/nuclei-templates/ -severity critical,high

# Trivy — container and infrastructure scanning
trivy image myapp:latest
trivy fs /path/to/project
trivy config /path/to/terraform
```

### Manual CVE Correlation

1. Map each service + version from nmap output
2. Search for known CVEs: `searchsploit <service version>`, NVD, CVE databases
3. Cross-reference with exploit-db, GitHub advisories

```bash
searchsploit apache 2.4.49
searchsploit -x 12345   # examine exploit details
```

### Web Application Testing (OWASP Top 10)

- **Tools:** `Burp Suite`, `OWASP ZAP`, `sqlmap`, `wfuzz`

| Category | What to Check |
|----------|---------------|
| Injection | SQL, command, LDAP, template injection |
| Broken Auth | Default creds, session handling, brute-force protection |
| Sensitive Data | TLS misconfig, exposed secrets in source/responses |
| XXE | XML parser configuration |
| Broken Access Control | IDOR, privilege escalation, missing function-level checks |
| Misconfig | Default pages, verbose errors, directory listing, CORS |
| XSS | Reflected, stored, DOM-based |
| Deserialization | Insecure object handling |
| Components | Outdated libraries (check with `npm audit`, `pip-audit`, `trivy`) |
| Logging | Insufficient logging, log injection |

---

## Phase 5: Configuration and Hardening Review

### OS-Level Checks

- **Tools:** `lynis`, `linux-exploit-suggester`, `linpeas`

```bash
# System audit
lynis audit system

# Check for kernel and sudo exploits (on your own host)
linux-exploit-suggester.sh
```

- Review: firewall rules (`iptables -L`, `ufw status`), open ports vs. required ports, running services, cron jobs, SUID/SGID binaries, world-writable files, user accounts and sudo permissions

### Container and Cloud

- **Tools:** `trivy`, `kube-bench`, `ScoutSuite`, `prowler`

```bash
# Kubernetes CIS benchmark
kube-bench run

# AWS security audit
prowler aws
```

---

## Phase 6: Documentation and Reporting

For each finding, record:

1. **Asset** — IP, hostname, service
2. **Vulnerability** — description, CVE if applicable
3. **Severity** — use CVSS or a consistent rating (Critical/High/Medium/Low/Info)
4. **Evidence** — tool output, screenshots, request/response
5. **Remediation** — specific fix or mitigation
6. **Verification** — how to confirm the fix works

### Recommended Output Workflow

```
nmap -oA scans/initial TARGET          # structured output
nuclei -o findings/nuclei.json -json   # JSON for parsing
```

Consolidate results into a structured report. Tools like `Dradis`, `Faraday`, or `PlexTrac` can help manage findings across multiple scans.

---

## Phase 7: Traffic Obfuscation and Stealth Techniques

During authorized penetration tests, controlling the visibility of your scan traffic is important for two reasons: (1) testing whether your IDS/IPS, WAF, and SOC can actually detect enumeration, and (2) reducing noise on production systems to avoid disruption. These techniques should only be used on infrastructure you own or with explicit written authorization.

### Scan Timing and Rate Control

Aggressive scanning is loud. Slowing down scans reduces the likelihood of triggering rate-based detection.

- **Tools:** `nmap` timing templates, `feroxbuster`/`gobuster` rate flags

```bash
# nmap timing templates (T0=paranoid, T1=sneaky, T2=polite)
nmap -sS -T2 -p- TARGET

# Fine-grained control: max 5 packets/sec, 500ms between probes
nmap -sS --max-rate 5 --scan-delay 500ms -p- TARGET

# Randomize port order (default in nmap, but explicit for clarity)
nmap -sS --randomize-hosts -p- TARGET

# Rate-limit directory brute-forcing
gobuster dir -u https://TARGET -w wordlist.txt -t 2 --delay 1s
feroxbuster -u https://TARGET -w wordlist.txt -t 2 --rate-limit 5
ffuf -u https://TARGET/FUZZ -w wordlist.txt -rate 5
```

| nmap Timing | Name | Probe Delay | Use Case |
|-------------|------|-------------|----------|
| `-T0` | Paranoid | 5 min | IDS evasion testing |
| `-T1` | Sneaky | 15 sec | IDS evasion testing |
| `-T2` | Polite | 400 ms | Reduced network impact |
| `-T3` | Normal | default | Standard scanning |
| `-T4` | Aggressive | fast | Lab/isolated environments |

### Packet Fragmentation

Splitting probe packets into smaller fragments can bypass simple packet-inspection firewalls and older IDS signatures.

```bash
# Fragment IP packets into 8-byte chunks
nmap -f -sS -p 80,443 TARGET

# Double fragmentation (16-byte fragments)
nmap -ff -sS -p 80,443 TARGET

# Set specific MTU (must be multiple of 8)
nmap --mtu 24 -sS -p 80,443 TARGET
```

> **Note:** Modern IDS/IPS reassembles fragments before inspection. This is primarily useful for testing whether your defenses handle fragmentation correctly.

### Decoy Scanning

Decoy scanning mixes your real source IP with spoofed source IPs so that the target's logs show scan traffic from multiple addresses, making it harder to isolate the true scanner.

```bash
# Use decoys: ME is your real IP inserted among decoys
nmap -D 10.0.0.5,10.0.0.6,ME,10.0.0.7 -sS -p 80,443 TARGET

# Random decoys
nmap -D RND:5 -sS -p 80,443 TARGET
```

> **Limitations:** Decoys only work for scans that don't require a full TCP handshake (SYN scans). The decoy hosts should be alive to avoid SYN flood artifacts.

### Source Port Manipulation

Some firewalls allow traffic from "trusted" source ports (e.g., DNS 53, HTTP 80). Sending scans from these ports can bypass poorly configured rules.

```bash
# Scan from source port 53 (DNS)
nmap -g 53 -sS -p 1-1024 TARGET

# Scan from source port 80 (HTTP)
nmap --source-port 80 -sS -p 1-1024 TARGET
```

### Idle (Zombie) Scanning

An idle scan uses a third-party host (the "zombie") to probe the target, so the target never sees your IP address. The zombie must have predictable IP ID sequence increments.

```bash
# Find a suitable zombie (look for incremental IP ID)
nmap --script ipidseq TARGET_ZOMBIE

# Perform idle scan through the zombie
nmap -sI ZOMBIE_IP -p 80,443,22 TARGET
```

> **Use case:** Testing whether your network detects indirect scanning techniques. The zombie must be a host you also control.

### Proxying and Tunneling Scan Traffic

Route enumeration traffic through proxies or tunnels to test network segmentation, egress filtering, and logging.

#### SOCKS Proxies

```bash
# Route nmap through a SOCKS4 proxy via proxychains
# /etc/proxychains4.conf: socks4 127.0.0.1 9050
proxychains4 nmap -sT -Pn -p 80,443 TARGET

# Route web enumeration through a SOCKS proxy
export ALL_PROXY=socks5://127.0.0.1:1080
gobuster dir -u https://TARGET -w wordlist.txt
```

> **Note:** Proxychains forces TCP connect scans (`-sT`). SYN scans and UDP scans cannot be proxied through SOCKS.

#### SSH Tunneling

```bash
# Dynamic SOCKS proxy through an SSH jump host you control
ssh -D 9050 -f -N user@JUMPHOST

# Then scan through it
proxychains4 nmap -sT -Pn TARGET
```

#### VPN Pivoting

- Use WireGuard or OpenVPN to route scan traffic through a host in the target network segment
- Useful for testing internal segmentation controls

### Spoofing and Custom Packet Crafting

For advanced IDS/firewall testing, craft packets with specific flags, payloads, or header values.

- **Tools:** `nmap`, `hping3`, `scapy`

```bash
# TCP SYN with specific flags via hping3
hping3 -S -p 80 --rand-source -c 5 TARGET

# Custom TTL to test firewall TTL-based filtering
nmap --ttl 64 -sS -p 80 TARGET

# Append random data to probe packets (evade length-based signatures)
nmap --data-length 32 -sS -p 80,443 TARGET
```

#### Scapy (Python)

```python
from scapy.all import *

# Craft a SYN packet with a custom source port and TTL
pkt = IP(dst="TARGET", ttl=128) / TCP(sport=53, dport=80, flags="S")
resp = sr1(pkt, timeout=2)
```

### HTTP-Layer Obfuscation

When performing web enumeration, modify HTTP characteristics to blend in with normal traffic or bypass WAF rules.

```bash
# Randomize User-Agent with ffuf
ffuf -u https://TARGET/FUZZ -w wordlist.txt \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)" \
  -rate 5

# Use a custom User-Agent with gobuster
gobuster dir -u https://TARGET -w wordlist.txt \
  -a "Mozilla/5.0 (compatible; Googlebot/2.1)"

# Burp Suite / ZAP: configure upstream proxy, rotate User-Agents,
# add jitter between requests in Intruder/Fuzzer settings
```

**WAF bypass patterns:**
- Rotate User-Agent strings from a list of legitimate browsers
- Add realistic headers (`Accept`, `Accept-Language`, `Referer`)
- Use HTTP/2 where supported (some WAFs inspect HTTP/1.1 more aggressively)
- Vary request paths with case changes, double encoding, or path normalization tricks to test WAF rule coverage

### DNS Enumeration Stealth

```bash
# Use a specific DNS resolver to avoid your ISP's logging
dig @9.9.9.9 example.com

# Slow down DNS brute-forcing
dnsenum --threads 1 --noreverse example.com

# Use DNS-over-HTTPS for resolution
# (in tools that support custom resolvers)
```

### MAC Address Spoofing (Local Network)

When testing on a local network segment, change your MAC address to avoid being fingerprinted by switch port security or NAC.

```bash
# Spoof MAC before scanning on LAN
ip link set eth0 down
macchanger -r eth0
ip link set eth0 up

# Nmap also supports MAC spoofing directly
nmap --spoof-mac Dell -sS -p- TARGET
nmap --spoof-mac 00:11:22:33:44:55 -sS -p- TARGET
```

---

## Phase 8: Obfuscation Best Practices

### When to Use Stealth Techniques

| Scenario | Recommended Approach |
|----------|---------------------|
| Testing your IDS/IPS detection capability | Use multiple evasion techniques, compare what gets caught |
| Production system enumeration (authorized) | Polite timing (`-T2`), rate limiting, off-peak hours |
| Lab or isolated environment | Speed over stealth — use `-T4`/`-T5` |
| Red team engagement with detection testing | Layer techniques: timing + fragmentation + proxy + custom UA |
| Validating WAF rules | HTTP-layer obfuscation, encoding variations |

### Layering Techniques

No single technique is sufficient against a well-configured defensive stack. Combine methods:

1. **Transport layer:** Timing control + fragmentation + source port manipulation
2. **Network layer:** Proxy/tunnel through a jump host + decoys
3. **Application layer:** User-Agent rotation + header normalization + request jitter
4. **Operational:** Scan during high-traffic periods, split scans across multiple source IPs you control

### Logging Your Own Evasion

Always capture your scan traffic alongside the target's defensive logs. This lets you correlate what was sent vs. what was detected.

```bash
# Capture all traffic to/from target during a scan
tcpdump -i eth0 -w scan_capture.pcap host TARGET &
TCPDUMP_PID=$!

# Run your scan
nmap -T2 -sS -p- TARGET -oA stealth_scan

# Stop capture
kill $TCPDUMP_PID
```

Then compare `scan_capture.pcap` against IDS alerts, firewall logs, and SIEM events to identify detection gaps.

### Common Pitfalls

- **Over-reliance on timing alone:** Slow scans still produce the same signatures — IDS correlation windows may catch them
- **Ignoring DNS leaks:** Tools may resolve hostnames through your default resolver, leaking intent
- **Fragmentation assumptions:** Most modern IDS/IPS reassembles fragments; don't assume this bypasses detection
- **Proxy misconfiguration:** Ensure DNS resolution also goes through the proxy (`proxychains` can leak DNS)
- **Forgetting outbound logging:** Your egress firewall or ISP may log the scan traffic even if the target doesn't detect it

### Defensive Takeaways

Use these techniques against your own infrastructure to answer:

- Does our IDS detect slow scans (`-T1`, `-T2`)?
- Do our firewalls properly reassemble fragmented packets?
- Does our WAF catch requests with rotated User-Agents or encoded payloads?
- Can our SOC correlate scan activity across multiple source IPs?
- Do our logs capture enough detail to reconstruct an attacker's enumeration?

---

## Quick Reference: Wordlists

| Purpose | Path (Kali/SecLists) |
|---------|----------------------|
| Directories | `/usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt` |
| Files | `/usr/share/seclists/Discovery/Web-Content/raft-medium-files.txt` |
| Subdomains | `/usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt` |
| Passwords | `/usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt` |
| Usernames | `/usr/share/seclists/Usernames/top-usernames-shortlist.txt` |
| SNMP | `/usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt` |

---

## Tool Installation Index

Install instructions for every tool referenced in this document, organized by the section where they first appear, then alphabetically within each section.

> **Prerequisites:** Most tools assume a Debian/Ubuntu-based system. On Kali Linux, the majority of these are pre-installed. Adjust package manager commands for your distribution (`dnf`, `pacman`, etc.). Tools installed via `go install` require Go 1.21+. Tools installed via `pip` should use a virtual environment.

---

### Phase 1: Passive Reconnaissance

#### amass

Subdomain enumeration and OSINT gathering.

```bash
# Via package manager (Kali)
sudo apt install amass

# Via Go
go install -v github.com/owasp-amass/amass/v4/...@master

# Via Snap
sudo snap install amass
```

#### dig / host / nslookup

DNS lookup utilities (part of `dnsutils`/`bind-utils`).

```bash
# Debian/Ubuntu/Kali
sudo apt install dnsutils

# RHEL/Fedora
sudo dnf install bind-utils
```

#### dnsenum

DNS enumeration and zone transfer tool.

```bash
sudo apt install dnsenum
```

#### dnsrecon

DNS reconnaissance tool.

```bash
sudo apt install dnsrecon

# Via pip
pip install dnsrecon
```

#### gitleaks

Scan git repos for secrets and credentials.

```bash
# Via Go
go install github.com/gitleaks/gitleaks/v8@latest

# Via Homebrew
brew install gitleaks

# Via package (Kali)
sudo apt install gitleaks
```

#### trufflehog

Find credentials in git history and other sources.

```bash
# Via Go
go install github.com/trufflesecurity/trufflehog/v3@latest

# Via Homebrew
brew install trufflehog

# Via pip
pip install trufflehog
```

#### whois

Domain registration lookup.

```bash
sudo apt install whois
```

---

### Phase 2: Active Host Discovery

#### arp-scan

Layer 2 network scanner for local network discovery.

```bash
sudo apt install arp-scan
```

#### masscan

High-speed port scanner.

```bash
sudo apt install masscan

# From source
git clone https://github.com/robertdavidgraham/masscan
cd masscan && make -j
sudo make install
```

#### nmap

Network scanner and NSE scripting engine. Used across nearly every phase.

```bash
sudo apt install nmap

# From source (latest version)
wget https://nmap.org/dist/nmap-7.95.tar.bz2
tar xjf nmap-7.95.tar.bz2
cd nmap-7.95 && ./configure && make && sudo make install
```

---

### Phase 3: Service Enumeration

#### crackmapexec

Network protocol attack and enumeration tool (SMB, MSSQL, etc.).

```bash
sudo apt install crackmapexec

# Via pip (use pipx for isolation)
pipx install crackmapexec
```

> **Note:** `crackmapexec` has been succeeded by `netexec` in active development. Consider `pipx install netexec` as a drop-in replacement.

#### enum4linux-ng

SMB/Samba enumeration tool (Python rewrite of enum4linux).

```bash
sudo apt install enum4linux-ng

# From source
git clone https://github.com/cddmp/enum4linux-ng
cd enum4linux-ng && pip install -r requirements.txt
```

#### feroxbuster

Fast, recursive web content discovery.

```bash
sudo apt install feroxbuster

# Via cargo (Rust)
cargo install feroxbuster

# Via snap
sudo snap install feroxbuster
```

#### ffuf

Fast web fuzzer for directory/vhost/parameter discovery.

```bash
sudo apt install ffuf

# Via Go
go install github.com/ffuf/ffuf/v2@latest
```

#### gobuster

Directory/file, DNS, and vhost brute-forcing tool.

```bash
sudo apt install gobuster

# Via Go
go install github.com/OJ/gobuster/v3@latest
```

#### ldapsearch

LDAP query tool (part of `ldap-utils`).

```bash
# Debian/Ubuntu/Kali
sudo apt install ldap-utils

# RHEL/Fedora
sudo dnf install openldap-clients
```

#### mongosh

MongoDB Shell for database interaction.

```bash
# Via MongoDB repo
wget -qO- https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
echo "deb [signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg] https://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt update && sudo apt install mongosh

# Via npm
npm install -g mongosh
```

#### mysql (client)

MySQL/MariaDB command-line client.

```bash
sudo apt install default-mysql-client
```

#### nikto

Web server vulnerability scanner.

```bash
sudo apt install nikto
```

#### onesixtyone

Fast SNMP community string scanner.

```bash
sudo apt install onesixtyone
```

#### psql

PostgreSQL command-line client.

```bash
sudo apt install postgresql-client
```

#### redis-cli

Redis command-line client.

```bash
sudo apt install redis-tools
```

#### rpcinfo / showmount

NFS and RPC enumeration tools (part of `nfs-common`).

```bash
sudo apt install nfs-common
```

#### smbclient

SMB/CIFS client for share enumeration and file access.

```bash
sudo apt install smbclient
```

#### smtp-user-enum

SMTP user enumeration via VRFY/EXPN/RCPT.

```bash
sudo apt install smtp-user-enum

# Via CPAN / from source
git clone https://github.com/pentestmonkey/smtp-user-enum
```

#### snmp-check

SNMP device enumerator.

```bash
sudo apt install snmpcheck
```

#### snmpwalk

SNMP tree walker (part of `snmp` package).

```bash
sudo apt install snmp
```

#### sqsh

Interactive MSSQL/Sybase client.

```bash
sudo apt install sqsh
```

#### ssh-audit

SSH server and client configuration auditor.

```bash
sudo apt install ssh-audit

# Via pip
pip install ssh-audit
```

#### sslyze

TLS/SSL configuration analyzer.

```bash
pip install sslyze
```

#### testssl.sh

TLS/SSL testing from the command line.

```bash
sudo apt install testssl.sh

# From source
git clone --depth 1 https://github.com/drwetter/testssl.sh.git
```

#### whatweb

Web technology fingerprinter.

```bash
sudo apt install whatweb
```

---

### Phase 4: Vulnerability Identification

#### Burp Suite

Web application security testing platform (GUI).

```bash
# Community Edition — download from PortSwigger
# https://portswigger.net/burp/communitydownload
# On Kali:
sudo apt install burpsuite
```

#### Nessus

Vulnerability scanner (commercial, free Essentials tier available).

```bash
# Download .deb from Tenable:
# https://www.tenable.com/products/nessus/nessus-essentials
sudo dpkg -i Nessus-*.deb
sudo systemctl start nessusd
# Access at https://localhost:8834
```

#### Nuclei

Template-based vulnerability scanner.

```bash
sudo apt install nuclei

# Via Go
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest

# Templates update
nuclei -update-templates
```

#### OpenVAS (Greenbone)

Open-source vulnerability scanner.

```bash
# Via Greenbone Community Edition (Docker recommended)
# https://greenbone.github.io/docs/latest/
sudo apt install gvm
sudo gvm-setup
```

#### OWASP ZAP

Web application security scanner (GUI + CLI).

```bash
sudo apt install zaproxy

# Via Snap
sudo snap install zaproxy --classic

# Via Docker
docker run -u zap -p 8080:8080 ghcr.io/zaproxy/zaproxy:stable
```

#### pip-audit

Python dependency vulnerability scanner.

```bash
pip install pip-audit
```

#### searchsploit

Offline Exploit-DB search tool (part of `exploitdb`).

```bash
sudo apt install exploitdb

# Update database
searchsploit -u
```

#### sqlmap

Automatic SQL injection detection and exploitation tool.

```bash
sudo apt install sqlmap

# From source
git clone --depth 1 https://github.com/sqlmapproject/sqlmap.git
```

#### Trivy

Container, filesystem, and IaC vulnerability scanner.

```bash
# Via apt repo
sudo apt install wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo gpg --dearmor -o /usr/share/keyrings/trivy.gpg
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt update && sudo apt install trivy

# Via Homebrew
brew install trivy
```

#### wfuzz

Web fuzzer for parameter and path discovery.

```bash
sudo apt install wfuzz

# Via pip
pip install wfuzz
```

---

### Phase 5: Configuration and Hardening Review

#### kube-bench

Kubernetes CIS Benchmark checker.

```bash
# Via Go
go install github.com/aquasecurity/kube-bench@latest

# Via Docker (run against current cluster)
docker run --pid=host -v /etc:/etc:ro -v /var:/var:ro aquasec/kube-bench:latest
```

#### linpeas

Linux privilege escalation auditing script.

```bash
# Download latest release
curl -L https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh -o linpeas.sh
chmod +x linpeas.sh
```

#### linux-exploit-suggester

Suggests kernel exploits based on OS version.

```bash
git clone https://github.com/The-Z-Labs/linux-exploit-suggester.git
chmod +x linux-exploit-suggester/linux-exploit-suggester.sh
```

#### lynis

System auditing and hardening tool.

```bash
sudo apt install lynis

# From source (latest)
git clone https://github.com/CISOfy/lynis
cd lynis && sudo ./lynis audit system
```

#### prowler

AWS/Azure/GCP security assessment tool.

```bash
pip install prowler

# Via Docker
docker run -ti --rm -v ~/.aws:/root/.aws toniblyx/prowler aws
```

#### ScoutSuite

Multi-cloud security auditing tool.

```bash
pip install scoutsuite
```

---

### Phase 6: Documentation and Reporting

#### Dradis

Collaborative security reporting platform.

```bash
# Docker (recommended)
docker run -p 3000:3000 dradis/dradis-ce

# From source (Ruby/Rails application)
# https://dradis.com/ce/documentation/install_kali.html
```

#### Faraday

Collaborative penetration testing and vulnerability management.

```bash
# Via pip
pip install faraday

# Via Docker
docker run -p 5985:5985 faradaysec/faraday:latest
```

---

### Phase 7: Traffic Obfuscation

#### hping3

TCP/IP packet assembler and analyzer.

```bash
sudo apt install hping3
```

#### macchanger

MAC address spoofing utility.

```bash
sudo apt install macchanger
```

#### proxychains4 (proxychains-ng)

Force TCP connections through SOCKS/HTTP proxies.

```bash
sudo apt install proxychains4

# From source
git clone https://github.com/rofl0r/proxychains-ng
cd proxychains-ng && ./configure && make && sudo make install
```

#### scapy

Python packet manipulation library.

```bash
pip install scapy

# On Kali
sudo apt install python3-scapy
```

#### tcpdump

Network packet capture and analysis.

```bash
sudo apt install tcpdump
```

---

### Wordlists and Supporting Resources

#### SecLists

Comprehensive collection of wordlists for security testing.

```bash
sudo apt install seclists

# From source
git clone https://github.com/danielmiessler/SecLists.git /opt/seclists
```

#### Wappalyzer

Browser extension for web technology fingerprinting.

```
# Install as browser extension from:
# Chrome Web Store or Firefox Add-ons
# Search "Wappalyzer"
#
# CLI alternative (Node.js):
npm install -g wappalyzer
```
