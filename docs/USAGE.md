# Enumethod Usage Guide

## Legal and Ethical Use

Enumethod is a penetration testing and security assessment tool. **You must have explicit written authorization before scanning any system you do not own.** Unauthorized scanning is illegal in most jurisdictions and can result in criminal prosecution.

### Before You Scan

1. **Obtain written authorization.** Ensure you have a signed Rules of Engagement (RoE) or equivalent document from the system owner that explicitly permits the types of testing Enumethod performs (port scanning, service enumeration, brute-forcing, vulnerability scanning).
2. **Verify scope.** Confirm which IP addresses, domains, and ports are in scope. Use the `--steps` and `--skip-*` flags to limit testing to authorized activities.
3. **Understand the impact.** Some enumeration steps are aggressive — brute-force attacks (step 10), vulnerability scanning (step 5), and authentication testing (step 6) can trigger IDS/IPS alerts, cause service disruptions, or lock out accounts. Discuss acceptable risk levels with the system owner.
4. **Document everything.** Keep records of authorization, scan configurations, timestamps, and findings. Enumethod's run history and reports serve as part of this documentation.

### Responsible Use Guidelines

- **Never scan production systems during business hours** unless explicitly authorized and the system owner accepts the risk of potential disruption.
- **Use the dry-run flag** (`--dry-run`) to preview commands before executing against a target for the first time.
- **Start with passive steps** (step 1) and lower timing values (`-t 2` or `-t 3`) before running aggressive scans.
- **Protect your findings.** Scan results may reveal sensitive vulnerabilities, credentials, and internal network architecture. Store and transmit reports securely. Delete scan data when the engagement ends unless retention is required.
- **Report vulnerabilities promptly** to the system owner with clear remediation guidance. The AI assessment feature can help structure findings by severity.
- **Role-based access matters.** Give view-only accounts to stakeholders who need to see results but shouldn't be able to launch scans. Reserve admin access for authorized testers.

### Legal Frameworks

Unauthorized access to computer systems is a criminal offense under laws including but not limited to:
- **United States** — Computer Fraud and Abuse Act (CFAA), 18 U.S.C. 1030
- **United Kingdom** — Computer Misuse Act 1990
- **European Union** — Directive 2013/40/EU on attacks against information systems
- **Germany** — StGB 202a-c (data espionage, phishing, data interception)
- **Australia** — Criminal Code Act 1995, Part 10.7

Always consult with legal counsel if you are unsure whether your planned testing activity is authorized.

---

## Getting Started

### Local Development

```bash
# Install dependencies
pnpm install

# Set up environment
cp .env.example .env
# Edit .env with your PostgreSQL connection string

# Generate Prisma client + run migrations
pnpm exec prisma generate
pnpm exec prisma db push

# Seed the database
pnpm exec tsx scripts/seed.ts

# Start dev servers (Next.js + Nest.js)
pnpm dev
```

The app will be available at:
- Frontend: http://localhost:3000
- API: http://localhost:3001
- API docs (Swagger): http://localhost:3001/api/docs

### Default Login
- Username: `admin`
- Password: `TestifyThusly99@`
- You'll be prompted to change the password on first login.

## Running an Enumeration

1. Log in and navigate to the **Dashboard**
2. Enter the target IP/hostname (required) and optional domain
3. Configure options:
   - **Steps**: Which of the 11 steps to run (comma-separated, or "all")
   - **Timing**: nmap timing template 0-5 (default: 4)
   - **Skip UDP**: Skip the slow UDP scan
   - **Skip Brute-force**: Skip directory/vhost brute-forcing
   - **Dry Run**: Print commands without executing
4. Click **Start Enumeration**

### Live Monitoring
- **Step Bar**: Visual progress through the 11 steps
- **Log Output**: Real-time terminal output via WebSocket
  - Use the filter box to search output
  - Auto-scroll toggles when you scroll up
- **Pause/Resume/Cancel**: Controls appear during active scans

## The 11 Steps

1. **Passive Recon & OSINT** — DNS, WHOIS, certificate transparency
2. **Active Host Discovery** — Ping sweep, ARP scan
3. **Port Scanning & Service Enum** — TCP/UDP port scans, service versions
4. **Web Stack Fingerprinting** — HTTP headers, CMS detection, tech stack
5. **Vulnerability Scanning** — Nuclei, nikto, CVE detection
6. **Authentication Testing** — SSH audit, login brute-force attempts
7. **SMB / NetBIOS / RPC** — SMB shares, null sessions, RPC endpoints
8. **SNMP Enumeration** — Community string testing, SNMP walks
9. **LDAP / NFS / Databases** — LDAP queries, NFS exports, DB probing
10. **Directory & VHost Brute-forcing** — Web directory and virtual host discovery
11. **Report Generation** — HTML report compilation

## Viewing Results

### Past Runs
Navigate to **Past Runs** to see all enumeration history. Each run shows:
- Target, domain, status, step progress, timing

### Run Detail
Click a run to see:
- **Output tab**: Expandable per-command output, searchable
- **Report tab**: Embedded HTML report (for completed runs)
- **AI Assessment tab**: AI-powered security analysis

### Reports
- **HTML Report**: View in browser or new tab
- **ZIP Export**: Download all scan output files

## AI Assessment

### Setup
1. Go to **Admin > Credentials**
2. Add a Claude or OpenAI API key
3. Optionally customize the prompt template in **Settings**

### Running an Assessment
1. Open a completed run's detail page
2. Go to the **AI Assessment** tab
3. Select a provider (Claude or OpenAI)
4. Click **Analyze with AI**

The AI will:
- Review all enumeration output
- Extract and enrich CVE IDs via the NVD database
- Provide findings categorized by severity
- Suggest remediation steps

## User Management (Admin Only)

### Creating Users
1. Go to **Admin > Users**
2. Click **Create User**
3. Choose role:
   - **Admin**: Can start/cancel scans, manage users, manage credentials, trigger AI
   - **View**: Can view runs and reports, change own password

### Password Reset
New users have `mustResetPassword=true` and will be forced to change their password on first login.

## Settings

### Password Change
Available to all users at **Settings > Change Password**.

### AI Prompt Template (Admin Only)
Customize the prompt sent to AI providers. Available variables:
- `{{target_ip}}` — Target IP address
- `{{domain}}` — Target domain
- `{{scan_date}}` — When the scan ran
- `{{run_output}}` — Combined enumeration output
- `{{cve_data}}` — Enriched CVE information
