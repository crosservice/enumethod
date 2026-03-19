# Enumethod v2 Architecture

## Overview

Enumethod v2 is a full-stack web application that wraps `enumerate.sh` (an 11-step automated penetration testing script) in a modern interface with real-time streaming, AI-powered analysis, and single-command deployment.

> **Authorization required.** This system is designed for authorized penetration testing engagements only. See [USAGE.md — Legal and Ethical Use](USAGE.md#legal-and-ethical-use) for requirements.

## Stack

| Layer      | Technology                        |
| ---------- | --------------------------------- |
| Frontend   | Next.js 14 (App Router) + Tailwind CSS |
| Backend    | Nest.js + Prisma ORM              |
| Database   | PostgreSQL                         |
| Real-time  | Socket.IO (WebSocket)              |
| Auth       | JWT (access 15min + refresh 7d)    |
| Encryption | AES-256-GCM (credential vault)     |
| Deploy     | Ubuntu 24.04 + nginx + systemd     |

## Monorepo Structure

```
enumethod/
├── apps/
│   ├── web/          # Next.js frontend
│   └── api/          # Nest.js backend
├── packages/
│   └── shared/       # Shared TypeScript types + constants
├── prisma/           # Database schema + migrations
├── scripts/          # Deploy/rebuild/seed scripts
├── enumerate.sh      # The enumeration script
└── docs/             # Documentation
```

Managed via **pnpm workspaces** + **Turborepo** for parallel builds.

## Data Flow

### Enumeration Run Lifecycle

```
User → ScanForm → POST /api/runs → RunManagerService
                                        ↓
                                  spawn enumerate.sh
                                        ↓
                              stdout parsed line-by-line
                                        ↓
                           ##ENUM_CMD_START/END## markers
                                        ↓
                    RunOutput records created in PostgreSQL
                                        ↓
                     Socket.IO emits to subscribed clients
                                        ↓
                         Browser renders live terminal output
```

### Pause/Resume

1. API writes `PAUSE` to `$OUTPUT_DIR/.enum_control`
2. `run_cmd()` in enumerate.sh checks this file between commands
3. Script emits `##ENUM_PAUSED##` and sleeps in a loop
4. API writes `RUN` to resume; script continues

### AI Assessment

1. Admin triggers assessment via `POST /api/runs/:id/assess`
2. AiService loads all RunOutput records for the run
3. CVE IDs extracted via regex, enriched via NVD API (capped at 20)
4. Prompt built from configurable template with variables
5. Claude or OpenAI called; response and severity summary saved
6. Frontend displays assessment with severity badges

## Authentication

- **Access token**: JWT, 15-minute expiry, sent as Bearer header
- **Refresh token**: JWT, 7-day expiry, stored as bcrypt hash in DB, rotated on each refresh
- **Force password reset**: If `mustResetPassword=true`, API blocks all routes except password change, frontend redirects to settings
- **Roles**: `admin` (full access) and `view` (read-only, can view runs but not start/cancel/manage)

## Credential Vault

API keys for AI providers are encrypted at rest using AES-256-GCM:
- Encryption key derived from `ENCRYPTION_SECRET` env var using PBKDF2 (100k iterations, SHA-512)
- Each credential stored with: encrypted ciphertext, IV (12 bytes), auth tag (16 bytes)
- Keys displayed masked (last 4 chars only) in the UI

## Database Schema

- **users**: Auth, roles, password management
- **runs**: Scan metadata, status state machine, PID tracking
- **run_outputs**: Per-command output with step number, exit code, timing
- **credentials**: Encrypted API keys for AI providers
- **ai_assessments**: AI analysis results with parsed severity summary
- **settings**: Key-value configuration (e.g., AI prompt template)

## WebSocket Protocol

Namespace: `/ws/runs`

| Event     | Direction      | Payload                                    |
| --------- | -------------- | ------------------------------------------ |
| subscribe | client → server | `{ runId: number }`                       |
| catchup   | server → client | `{ lines: string[], step, command, status }` |
| output    | server → client | `{ line: string, step, command }`         |
| status    | server → client | `{ status: string, step }`                |

Clients authenticate via `auth.token` in the Socket.IO handshake.

## Security

- Helmet HTTP headers, CORS restricted to frontend origin
- class-validator with whitelist + forbidNonWhitelisted on all DTOs
- Rate limiting: 5/min on login, 100/min global
- nginx: hidden version, HSTS, security headers, rate limiting
- Fail2ban jails for SSH, nginx auth, rate limits
- UFW firewall (SSH + HTTP/HTTPS only)
- Kernel hardening (SYN cookies, anti-spoofing, ASLR)
