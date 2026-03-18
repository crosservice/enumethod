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

## Quick Reference: Wordlists

| Purpose | Path (Kali/SecLists) |
|---------|----------------------|
| Directories | `/usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt` |
| Files | `/usr/share/seclists/Discovery/Web-Content/raft-medium-files.txt` |
| Subdomains | `/usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt` |
| Passwords | `/usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt` |
| Usernames | `/usr/share/seclists/Usernames/top-usernames-shortlist.txt` |
| SNMP | `/usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt` |
