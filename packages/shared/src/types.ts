import type { RUN_STATUSES, USER_ROLES, AI_PROVIDERS } from './constants';

// ── Enums ───────────────────────────────────────────────────────────────────

export type RunStatus = (typeof RUN_STATUSES)[number];
export type UserRole = (typeof USER_ROLES)[number];
export type AiProvider = (typeof AI_PROVIDERS)[number];

// ── User ────────────────────────────────────────────────────────────────────

export interface User {
  id: number;
  username: string;
  role: UserRole;
  mustResetPassword: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CreateUserDto {
  username: string;
  password: string;
  role: UserRole;
}

export interface UpdateUserDto {
  role?: UserRole;
  password?: string;
}

export interface ChangePasswordDto {
  currentPassword: string;
  newPassword: string;
  confirmPassword: string;
}

// ── Auth ────────────────────────────────────────────────────────────────────

export interface LoginDto {
  username: string;
  password: string;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
}

export interface JwtPayload {
  sub: number;
  username: string;
  role: UserRole;
  mustReset: boolean;
}

// ── Run ─────────────────────────────────────────────────────────────────────

export interface Run {
  id: number;
  targetIp: string;
  domain: string;
  arguments: RunArguments;
  status: RunStatus;
  currentStep: number;
  currentCommand: string | null;
  outputDir: string;
  pid: number | null;
  startedAt: string | null;
  finishedAt: string | null;
  pausedAt: string | null;
  createdBy: number;
}

export interface RunArguments {
  domain?: string;
  steps?: string;
  timing?: number;
  wordlist?: string;
  skipUdp?: boolean;
  skipBruteforce?: boolean;
  dryRun?: boolean;
}

export interface CreateRunDto {
  targetIp: string;
  domain?: string;
  steps?: string;
  timing?: number;
  wordlist?: string;
  skipUdp?: boolean;
  skipBruteforce?: boolean;
  dryRun?: boolean;
}

export interface RunOutput {
  id: number;
  runId: number;
  stepNumber: number;
  commandName: string;
  outputText: string;
  startedAt: string | null;
  finishedAt: string | null;
  exitCode: number | null;
}

// ── Credentials ─────────────────────────────────────────────────────────────

export interface Credential {
  id: number;
  name: string;
  provider: AiProvider;
  maskedKey: string;
  createdAt: string;
  updatedAt: string;
}

export interface CreateCredentialDto {
  name: string;
  provider: AiProvider;
  apiKey: string;
}

// ── AI Assessment ───────────────────────────────────────────────────────────

export interface AiAssessment {
  id: number;
  runId: number;
  provider: AiProvider;
  promptUsed: string;
  response: string;
  severitySummary: SeveritySummary | null;
  createdAt: string;
}

export interface SeveritySummary {
  critical: number;
  high: number;
  medium: number;
  low: number;
  info: number;
  findings: Finding[];
}

export interface Finding {
  title: string;
  severity: 'critical' | 'high' | 'medium' | 'low' | 'info';
  description: string;
  remediation: string;
}

export interface TriggerAssessmentDto {
  provider: AiProvider;
}

// ── Settings ────────────────────────────────────────────────────────────────

export interface Setting {
  id: number;
  key: string;
  value: string;
  updatedAt: string;
}

export interface UpdateSettingDto {
  value: string;
}

// ── WebSocket Events ────────────────────────────────────────────────────────

export interface WsCatchupPayload {
  lines: string[];
  step: number;
  command: string | null;
  status: RunStatus;
}

export interface WsOutputPayload {
  line: string;
  step: number;
  command: string | null;
}

export interface WsStatusPayload {
  status: RunStatus;
  step: number;
}

// ── API Response ────────────────────────────────────────────────────────────

export interface ApiError {
  statusCode: number;
  message: string;
  error?: string;
}

export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
}
