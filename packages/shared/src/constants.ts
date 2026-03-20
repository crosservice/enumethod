export const STEP_NAMES: Record<number, string> = {
  1: 'Passive Recon & OSINT',
  2: 'Active Host Discovery',
  3: 'Port Scanning & Service Enum',
  4: 'Web Stack Fingerprinting',
  5: 'Vulnerability Scanning',
  6: 'Authentication Testing',
  7: 'SMB / NetBIOS / RPC',
  8: 'SNMP Enumeration',
  9: 'LDAP / NFS / Databases',
  10: 'Directory & VHost Brute-forcing',
  11: 'Report Generation',
};

export const TOTAL_STEPS = 11;

export const RUN_STATUSES = [
  'pending',
  'running',
  'paused',
  'completed',
  'failed',
  'cancelled',
] as const;

export const USER_ROLES = ['admin', 'view'] as const;

export const AI_PROVIDERS = ['claude', 'openai'] as const;

export const WS_EVENTS = {
  SUBSCRIBE: 'subscribe',
  CATCHUP: 'catchup',
  OUTPUT: 'output',
  STATUS: 'status',
  ERROR: 'error',
} as const;

export const COMMAND_MARKERS = {
  START: '##ENUM_CMD_START::',
  END: '##ENUM_CMD_END::',
  SKIP: '##ENUM_CMD_SKIP::',
  PAUSED: '##ENUM_PAUSED##',
  SEPARATOR: '::',
  SUFFIX: '##',
} as const;

export const DEFAULT_AI_PROMPT_TEMPLATE = `You are a senior penetration tester reviewing automated enumeration results.

Target: {{target_ip}}
Domain: {{domain}}
Scan Date: {{scan_date}}

## Enumeration Output
{{run_output}}

## CVE Data
{{cve_data}}

Provide a security assessment with:
1. Executive Summary (2-3 sentences)
2. Critical Findings (severity: critical/high/medium/low/info)
3. Attack Vectors identified
4. Recommended Remediation Steps
5. Overall Risk Rating

At the end of your response, provide a JSON code block with exactly this structure (use integer counts):
\`\`\`json
{
  "critical": 0,
  "high": 0,
  "medium": 0,
  "low": 0,
  "info": 0,
  "findings": [
    {"title": "...", "severity": "critical|high|medium|low|info", "description": "...", "remediation": "..."}
  ]
}
\`\`\``;
