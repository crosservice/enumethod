# Server Enumeration Methodology

A structured approach to identifying vulnerabilities on servers you own or have explicit authorization to test.

---

## Attack Chain: End-to-End Enumeration Playbook

This section walks through the full enumeration chain an attacker would follow against a target server, step by step, with exact commands. Use this on systems you own or have written authorization to test. Each step feeds into the next — output from earlier stages drives the targeting in later stages.

> **Convention:** `TARGET` = IP or hostname. `DOMAIN` = target domain. Replace these throughout.

---

### Step 1: Passive Intelligence Gathering

Collect as much information as possible without touching the target directly. This leaves zero footprint.

```bash
# 1a. WHOIS — identify registrant, IP blocks, name servers
whois DOMAIN
whois TARGET

# 1b. DNS records — find subdomains, mail servers, SPF/DKIM, name servers
dig any DOMAIN
dig txt DOMAIN
dig mx DOMAIN
dig ns DOMAIN

# 1c. Zone transfer — if misconfigured, dumps the entire DNS zone
dig axfr DOMAIN @$(dig ns DOMAIN +short | head -1)

# 1d. Subdomain enumeration — passive sources (no direct target contact)
amass enum -passive -d DOMAIN -o passive_subs.txt

# 1e. Certificate transparency — find additional hostnames from TLS certs
curl -s "https://crt.sh/?q=%25.DOMAIN&output=json" | jq -r '.[].name_value' | sort -u > ct_subs.txt

# 1f. Combine and deduplicate all discovered hostnames
cat passive_subs.txt ct_subs.txt | sort -u > all_subs.txt

# 1g. Resolve discovered subdomains to IP addresses
while read sub; do
  ip=$(dig +short "$sub" | head -1)
  [ -n "$ip" ] && echo "$sub -> $ip"
done < all_subs.txt | tee resolved_hosts.txt

# 1h. Search for leaked credentials and secrets in public repos
gitleaks detect --source="https://github.com/TARGET_ORG" --report-path=gitleaks_report.json
trufflehog github --org=TARGET_ORG --json > trufflehog_results.json
```

**What you have now:** A list of hostnames, IPs, mail servers, name servers, and potentially leaked credentials — all gathered without the target seeing a single packet from you.

---

### Step 2: Active Host Discovery and Port Scanning

Now touch the target. Start broad and fast, then go deep on what you find.

```bash
# 2a. Ping sweep — which hosts are alive? (skip if target blocks ICMP)
nmap -sn -T4 TARGET/24 -oG alive_hosts.txt
grep "Up" alive_hosts.txt | awk '{print $2}' > live_ips.txt

# 2b. Fast SYN scan — all 65535 TCP ports on live hosts
nmap -sS -p- --min-rate 10000 -T4 -iL live_ips.txt -oA tcp_all_ports

# 2c. Extract open ports for targeted deep scan
grep "open" tcp_all_ports.gnmap | awk -F'/' '{print $1}' | \
  awk '{print $NF}' | sort -un | tr '\n' ',' > open_ports.txt

# 2d. Service version detection + default scripts on discovered ports
nmap -sV -sC -O -p$(cat open_ports.txt) -iL live_ips.txt -oA detailed_scan

# 2e. UDP scan — top 50 most common UDP services
nmap -sU --top-ports 50 -T4 -iL live_ips.txt -oA udp_scan

# 2f. Aggressive OS fingerprinting on key targets
nmap -O --osscan-guess TARGET -oA os_fingerprint
```

**What you have now:** A complete port map, service versions, OS guesses, and NSE script output for every live host. This is the foundation for all targeted enumeration.

---

### Step 3: Web Service Enumeration (80/443)

Web services are the most common and most exploitable attack surface. Enumerate thoroughly.

```bash
# 3a. Technology fingerprinting — what stack is running?
whatweb -a 3 https://TARGET | tee whatweb_output.txt

# 3b. TLS configuration audit
testssl.sh --quiet https://TARGET | tee tls_audit.txt

# 3c. Directory and file brute-force — find hidden content
feroxbuster -u https://TARGET \
  -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt \
  -x php,html,txt,bak,conf,json,xml,asp,aspx,jsp \
  -t 20 --rate-limit 100 \
  -o ferox_dirs.txt

# 3d. Check for sensitive file exposure
curl -s -o /dev/null -w "%{http_code}" https://TARGET/.git/HEAD
curl -s -o /dev/null -w "%{http_code}" https://TARGET/.env
curl -s -o /dev/null -w "%{http_code}" https://TARGET/robots.txt
curl -s -o /dev/null -w "%{http_code}" https://TARGET/sitemap.xml
curl -s -o /dev/null -w "%{http_code}" https://TARGET/.DS_Store
curl -s -o /dev/null -w "%{http_code}" https://TARGET/server-status
curl -s -o /dev/null -w "%{http_code}" https://TARGET/wp-config.php.bak

# 3e. Virtual host enumeration — find sites sharing the same IP
ffuf -u https://TARGET -H "Host: FUZZ.DOMAIN" \
  -w /usr/share/seclists/Discovery/DNS/subdomains-top1million-5000.txt \
  -fc 301,302,404 -o vhost_results.json

# 3f. Vulnerability scan against web server
nikto -h https://TARGET -output nikto_results.txt

# 3g. Screenshot all discovered web services for quick visual review
# (requires gowitness or eyewitness)
gowitness file -f urls.txt --screenshot-path ./screenshots/
```

**What you have now:** Full picture of the web stack — technology, TLS posture, hidden files/directories, virtual hosts, and known vulnerabilities.

---

### Step 4: Authentication Service Enumeration (SSH, RDP, FTP)

Probe services that accept credentials for weaknesses.

```bash
# 4a. SSH — audit configuration, algorithms, and auth methods
ssh-audit TARGET | tee ssh_audit.txt
nmap --script ssh2-enum-algos,ssh-auth-methods -p 22 TARGET

# 4b. FTP — check for anonymous access
nmap --script ftp-anon,ftp-syst -p 21 TARGET

# 4c. RDP — check encryption and NLA status
nmap --script rdp-enum-encryption,rdp-ntlm-info -p 3389 TARGET
```

**What you have now:** Whether SSH allows weak algorithms or password auth, whether FTP allows anonymous login, and RDP security posture.

---

### Step 5: Windows / SMB / Active Directory Enumeration (139/445)

If the target runs Windows or Samba, SMB is a goldmine.

```bash
# 5a. Full SMB enumeration — shares, users, groups, policies, OS info
enum4linux-ng -A TARGET | tee enum4linux_output.txt

# 5b. List accessible shares (null session)
smbclient -L //TARGET -N
crackmapexec smb TARGET --shares -u '' -p ''

# 5c. Check for critical SMB vulnerabilities
nmap --script smb-vuln-ms17-010,smb-vuln-ms08-067,smb-vuln-cve-2020-0796 -p 445 TARGET

# 5d. Enumerate users via RID cycling (no credentials needed)
crackmapexec smb TARGET -u '' -p '' --rid-brute

# 5e. If credentials are obtained, go deeper
crackmapexec smb TARGET -u USER -p PASS --shares --sessions --disks --loggedon-users
```

**What you have now:** Share permissions, user accounts, group memberships, password policies, and whether the host is vulnerable to EternalBlue or SMBGhost.

---

### Step 6: Mail and Messaging Enumeration (SMTP/POP3/IMAP)

Email services leak usernames and may allow relay abuse.

```bash
# 6a. SMTP user enumeration via VRFY
smtp-user-enum -M VRFY -U /usr/share/seclists/Usernames/top-usernames-shortlist.txt -t TARGET

# 6b. SMTP user enumeration via RCPT TO (if VRFY is disabled)
smtp-user-enum -M RCPT -U /usr/share/seclists/Usernames/top-usernames-shortlist.txt -t TARGET

# 6c. Open relay check — can you send mail through this server?
nmap --script smtp-open-relay -p 25 TARGET

# 6d. Grab SMTP banner and supported commands
nmap --script smtp-commands,smtp-ntlm-info -p 25,465,587 TARGET
```

**What you have now:** Valid usernames harvested via SMTP, relay status, and server configuration details.

---

### Step 7: SNMP Enumeration (161/UDP)

SNMP with weak community strings can dump system configuration, interfaces, routing tables, and running processes.

```bash
# 7a. Brute-force community strings
onesixtyone -c /usr/share/seclists/Discovery/SNMP/common-snmp-community-strings.txt TARGET

# 7b. If community string is found (e.g., "public"), walk the full MIB tree
snmpwalk -v2c -c public TARGET | tee snmpwalk_full.txt

# 7c. Targeted OID walks for high-value data
snmpwalk -v2c -c public TARGET 1.3.6.1.2.1.1       # System info
snmpwalk -v2c -c public TARGET 1.3.6.1.2.1.25.4.2  # Running processes
snmpwalk -v2c -c public TARGET 1.3.6.1.2.1.6.13    # TCP connections
snmpwalk -v2c -c public TARGET 1.3.6.1.2.1.25.6.3  # Installed software

# 7d. Automated SNMP enumeration
snmp-check TARGET -c public | tee snmpcheck_output.txt
```

**What you have now:** System description, network interfaces, running processes, installed software, TCP connection table — massive recon from a single misconfigured service.

---

### Step 8: Database Enumeration (3306/5432/1433/6379/27017)

Exposed databases are often misconfigured or use default credentials.

```bash
# 8a. MySQL — check for anonymous/root access
nmap --script mysql-info,mysql-enum,mysql-empty-password -p 3306 TARGET
mysql -h TARGET -u root -p'' -e "SELECT user,host FROM mysql.user;" 2>/dev/null

# 8b. PostgreSQL — default credentials and database listing
nmap --script pgsql-brute -p 5432 TARGET
psql -h TARGET -U postgres -c "\l" 2>/dev/null

# 8c. MSSQL — instance discovery, info gathering
nmap --script ms-sql-info,ms-sql-ntlm-info,ms-sql-empty-password -p 1433 TARGET

# 8d. Redis — unauthenticated access check
redis-cli -h TARGET INFO server 2>/dev/null
redis-cli -h TARGET CONFIG GET dir 2>/dev/null

# 8e. MongoDB — unauthenticated access check
nmap --script mongodb-info,mongodb-databases -p 27017 TARGET
mongosh --host TARGET --eval "db.adminCommand('listDatabases')" 2>/dev/null
```

**What you have now:** Whether databases accept unauthenticated connections, user lists, database inventories, and configuration details.

---

### Step 9: NFS, RPC, and LDAP Enumeration

These services often expose file systems and directory information without authentication.

```bash
# 9a. RPC — list registered services
rpcinfo -p TARGET

# 9b. NFS — list exported shares and check mount permissions
showmount -e TARGET
# If a share is mountable:
mkdir /tmp/nfs_mount && sudo mount -t nfs TARGET:/share /tmp/nfs_mount

# 9c. LDAP — anonymous bind and base enumeration
ldapsearch -x -H ldap://TARGET -b "" -s base namingContexts
ldapsearch -x -H ldap://TARGET -b "dc=DOMAIN,dc=com" "(objectClass=*)" | tee ldap_dump.txt

# 9d. LDAP user enumeration
ldapsearch -x -H ldap://TARGET -b "dc=DOMAIN,dc=com" "(objectClass=person)" cn sAMAccountName
```

**What you have now:** Mountable file shares, exported directories, and full LDAP directory dumps including user accounts.

---

### Step 10: Automated Vulnerability Scanning

With full service knowledge, run targeted vulnerability scanners for CVE identification.

```bash
# 10a. Nuclei — fast, template-based vuln scanning
nuclei -u https://TARGET -t cves/ -t misconfigurations/ -t exposures/ \
  -severity critical,high,medium -o nuclei_results.txt

# 10b. Nmap vuln scripts — cross-service CVE checks
nmap --script vuln -p$(cat open_ports.txt) TARGET -oA vuln_scan

# 10c. searchsploit — correlate every discovered service version
# Extract versions from nmap output and search each one:
grep "open" detailed_scan.nmap | while read line; do
  service=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf $i " "; print ""}')
  echo "=== $service ===" >> searchsploit_results.txt
  searchsploit "$service" >> searchsploit_results.txt 2>&1
done

# 10d. Web application vulnerability scan
sqlmap -u "https://TARGET/page?id=1" --batch --crawl=3 --forms --risk=2 --level=3
```

**What you have now:** A prioritized list of known CVEs and exploitable conditions mapped to every discovered service.

---

### Step 11: Consolidate and Prioritize Findings

Bring everything together into a structured attack surface map.

```bash
# 11a. Organize all output
mkdir -p results/{passive,ports,web,auth,smb,mail,snmp,db,nfs,vulns}
mv passive_subs.txt ct_subs.txt resolved_hosts.txt gitleaks_report.json trufflehog_results.json results/passive/
mv tcp_all_ports.* detailed_scan.* udp_scan.* os_fingerprint.* results/ports/
mv whatweb_output.txt tls_audit.txt ferox_dirs.txt vhost_results.json nikto_results.txt results/web/
mv ssh_audit.txt results/auth/
mv enum4linux_output.txt results/smb/
mv snmpwalk_full.txt snmpcheck_output.txt results/snmp/
mv nuclei_results.txt vuln_scan.* searchsploit_results.txt results/vulns/

# 11b. Generate a summary of all open ports and services
grep "open" detailed_scan.nmap | sort -t/ -k1 -n > results/service_summary.txt

# 11c. Count findings by severity (nuclei output)
echo "=== Finding Severity Summary ===" > results/summary.txt
grep -c "critical" nuclei_results.txt | xargs -I{} echo "Critical: {}" >> results/summary.txt
grep -c "high" nuclei_results.txt | xargs -I{} echo "High: {}" >> results/summary.txt
grep -c "medium" nuclei_results.txt | xargs -I{} echo "Medium: {}" >> results/summary.txt
cat results/summary.txt
```

**What you have now:** A complete, organized attack surface map with prioritized vulnerabilities ready for exploitation or remediation.

---

### Quick Reference: The Chain at a Glance

```
Step 1:  Passive recon    ──→  Hostnames, IPs, leaked creds
Step 2:  Port scan        ──→  Open ports, service versions, OS
Step 3:  Web enumeration  ──→  Directories, tech stack, vhosts, vulns
Step 4:  Auth services    ──→  SSH/FTP/RDP config weaknesses
Step 5:  SMB/AD           ──→  Shares, users, groups, SMB vulns
Step 6:  Mail             ──→  Valid usernames, relay status
Step 7:  SNMP             ──→  System info, processes, network config
Step 8:  Databases        ──→  Unauth access, user lists, data
Step 9:  NFS/RPC/LDAP     ──→  File shares, directory users
Step 10: Vuln scanning    ──→  CVEs mapped to services
Step 11: Consolidate      ──→  Prioritized attack surface map
```

Each step's output feeds the next. Credentials found in Step 1 feed into Step 5. Usernames from Step 6 feed into brute-force in Step 4. Service versions from Step 2 drive CVE lookups in Step 10. The chain is iterative — new discoveries send you back to earlier steps with better targeting.

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
