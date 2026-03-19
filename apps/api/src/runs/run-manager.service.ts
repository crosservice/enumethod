import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ChildProcess, spawn } from 'child_process';
import * as readline from 'readline';
import * as fs from 'fs';
import * as path from 'path';
import { PrismaService } from '../prisma/prisma.service';
import { RunsGateway } from './runs.gateway';

interface ActiveRun {
  process: ChildProcess;
  lines: string[];
  currentStep: number;
  currentCommand: string | null;
  currentOutputId: number | null;
  cancelled: boolean;
}

const CMD_START_RE = /^##ENUM_CMD_START::(.+?)::(.+?)##$/;
const CMD_END_RE = /^##ENUM_CMD_END::(.+?)::(\d+)##$/;
const CMD_SKIP_RE = /^##ENUM_CMD_SKIP::(.+?)::(.+?)##$/;
const PAUSED_RE = /^##ENUM_PAUSED##$/;
const STEP_RE = /Step\s+(\d+)\/11:/;
const ANSI_RE = /\x1b\[[0-9;]*m/g;

@Injectable()
export class RunManagerService implements OnModuleInit {
  private readonly logger = new Logger(RunManagerService.name);
  private activeRuns = new Map<number, ActiveRun>();

  constructor(
    private prisma: PrismaService,
    private config: ConfigService,
    private gateway: RunsGateway,
  ) {}

  async onModuleInit() {
    // Mark stale running runs as failed on startup
    await this.prisma.run.updateMany({
      where: { status: 'running' },
      data: { status: 'failed' },
    });
  }

  async startRun(runId: number, targetIp: string, args: Record<string, unknown>) {
    const run = await this.prisma.run.findUnique({ where: { id: runId } });
    if (!run) throw new Error('Run not found');

    const scriptPath = this.config.get('SCRIPT_PATH', '/opt/enumethod/enumerate.sh');
    const cmd = ['sudo', scriptPath, targetIp, '-o', run.outputDir];

    if (args.domain) cmd.push('-d', String(args.domain));
    if (args.steps) cmd.push('-s', String(args.steps));
    if (args.timing !== undefined) cmd.push('-t', String(args.timing));
    if (args.skipUdp) cmd.push('--skip-udp');
    if (args.skipBruteforce) cmd.push('--skip-bruteforce');
    if (args.dryRun) cmd.push('--dry-run');
    if (args.wordlist) cmd.push('-w', String(args.wordlist));

    const proc = spawn(cmd[0], cmd.slice(1), {
      cwd: path.dirname(scriptPath),
      stdio: ['ignore', 'pipe', 'pipe'],
      detached: true,
    });

    const state: ActiveRun = {
      process: proc,
      lines: [],
      currentStep: 0,
      currentCommand: null,
      currentOutputId: null,
      cancelled: false,
    };

    this.activeRuns.set(runId, state);

    await this.prisma.run.update({
      where: { id: runId },
      data: { pid: proc.pid },
    });

    // Read stdout line by line
    if (proc.stdout) {
      const rl = readline.createInterface({ input: proc.stdout });
      rl.on('line', (raw) => this.handleLine(runId, raw));
    }

    // Also capture stderr
    if (proc.stderr) {
      const rl = readline.createInterface({ input: proc.stderr });
      rl.on('line', (raw) => this.handleLine(runId, raw));
    }

    proc.on('close', (code) => this.handleExit(runId, code));
    proc.on('error', (err) => {
      this.logger.error(`Run ${runId} process error: ${err.message}`);
      this.handleExit(runId, 1);
    });
  }

  private async handleLine(runId: number, raw: string) {
    const state = this.activeRuns.get(runId);
    if (!state) return;

    const clean = raw.replace(ANSI_RE, '');

    // Check for command start marker
    const startMatch = clean.match(CMD_START_RE);
    if (startMatch) {
      const [, desc, outfile] = startMatch;
      state.currentCommand = desc;

      // Create a new RunOutput record
      const output = await this.prisma.runOutput.create({
        data: {
          runId,
          stepNumber: state.currentStep,
          commandName: desc,
          outputText: '',
          startedAt: new Date(),
        },
      });
      state.currentOutputId = output.id;

      await this.prisma.run.update({
        where: { id: runId },
        data: { currentCommand: desc },
      });

      this.gateway.emitOutput(runId, clean, state.currentStep, desc);
      state.lines.push(clean);
      return;
    }

    // Check for command end marker
    const endMatch = clean.match(CMD_END_RE);
    if (endMatch) {
      const [, desc, exitCodeStr] = endMatch;
      const exitCode = parseInt(exitCodeStr, 10);

      if (state.currentOutputId) {
        await this.prisma.runOutput.update({
          where: { id: state.currentOutputId },
          data: { finishedAt: new Date(), exitCode },
        });
        state.currentOutputId = null;
      }

      state.currentCommand = null;
      await this.prisma.run.update({
        where: { id: runId },
        data: { currentCommand: null },
      });

      this.gateway.emitOutput(runId, clean, state.currentStep, null);
      state.lines.push(clean);
      return;
    }

    // Check for skip marker
    const skipMatch = clean.match(CMD_SKIP_RE);
    if (skipMatch) {
      const [, desc, reason] = skipMatch;
      await this.prisma.runOutput.create({
        data: {
          runId,
          stepNumber: state.currentStep,
          commandName: desc,
          outputText: `Skipped: ${reason}`,
          startedAt: new Date(),
          finishedAt: new Date(),
          exitCode: -1,
        },
      });
      this.gateway.emitOutput(runId, clean, state.currentStep, null);
      state.lines.push(clean);
      return;
    }

    // Check for paused marker
    if (PAUSED_RE.test(clean)) {
      await this.prisma.run.update({
        where: { id: runId },
        data: { status: 'paused', pausedAt: new Date() },
      });
      this.gateway.emitStatus(runId, 'paused', state.currentStep);
      return;
    }

    // Detect step transitions
    const stepMatch = clean.match(STEP_RE);
    if (stepMatch) {
      state.currentStep = parseInt(stepMatch[1], 10);
      await this.prisma.run.update({
        where: { id: runId },
        data: { currentStep: state.currentStep },
      });
    }

    // Append to current RunOutput
    if (state.currentOutputId) {
      await this.prisma.$executeRaw`
        UPDATE run_outputs
        SET output_text = output_text || ${clean + '\n'}
        WHERE id = ${state.currentOutputId}
      `;
    }

    // Emit to WebSocket subscribers
    this.gateway.emitOutput(runId, clean, state.currentStep, state.currentCommand);
    state.lines.push(clean);
  }

  private compileErrorLog(state: ActiveRun, code: number | null): string {
    const errorLines: string[] = [];

    // Collect lines containing errors, warnings, failures
    for (const line of state.lines) {
      if (
        line.includes('[-]') ||
        line.includes('[!]') ||
        line.includes('[SKIP]') ||
        line.includes('ENUM_CMD_SKIP') ||
        line.includes('error') ||
        line.includes('Error') ||
        line.includes('FAILED') ||
        line.includes('failed') ||
        line.includes('Permission denied') ||
        line.includes('not found') ||
        line.includes('No such file') ||
        (line.includes('ENUM_CMD_END') && !line.includes('::0##'))
      ) {
        errorLines.push(line);
      }
    }

    // Always include the last 20 lines for context
    const tail = state.lines.slice(-20);

    const parts: string[] = [];
    parts.push(`Exit code: ${code}`);
    parts.push(`Total output lines: ${state.lines.length}`);
    parts.push(`Last step reached: ${state.currentStep}/11`);
    parts.push('');

    if (errorLines.length > 0) {
      parts.push(`── Errors & Warnings (${errorLines.length} lines) ──`);
      // Cap at 200 error lines to avoid huge logs
      parts.push(...errorLines.slice(0, 200));
      if (errorLines.length > 200) {
        parts.push(`... and ${errorLines.length - 200} more`);
      }
      parts.push('');
    }

    parts.push('── Last 20 Lines ──');
    parts.push(...tail);

    return parts.join('\n');
  }

  private async handleExit(runId: number, code: number | null) {
    const state = this.activeRuns.get(runId);
    if (!state) return;

    let status: string;
    if (state.cancelled) {
      status = 'cancelled';
    } else if (code === 0) {
      status = 'completed';
    } else {
      status = 'failed';
    }

    // Compile error log for non-successful runs
    const errorLog = status !== 'completed'
      ? this.compileErrorLog(state, code)
      : null;

    await this.prisma.run.update({
      where: { id: runId },
      data: { status, finishedAt: new Date(), errorLog },
    });

    this.gateway.emitStatus(runId, status, state.currentStep);
    this.activeRuns.delete(runId);
    this.logger.log(`Run ${runId} finished with status: ${status}`);
  }

  async pauseRun(runId: number) {
    const run = await this.prisma.run.findUnique({ where: { id: runId } });
    if (!run || run.status !== 'running') return false;

    const controlFile = path.join(run.outputDir, '.enum_control');
    fs.mkdirSync(run.outputDir, { recursive: true });
    fs.writeFileSync(controlFile, 'PAUSE');

    await this.prisma.run.update({
      where: { id: runId },
      data: { status: 'paused', pausedAt: new Date() },
    });

    return true;
  }

  async resumeRun(runId: number) {
    const run = await this.prisma.run.findUnique({ where: { id: runId } });
    if (!run || run.status !== 'paused') return false;

    const controlFile = path.join(run.outputDir, '.enum_control');
    fs.writeFileSync(controlFile, 'RUN');

    await this.prisma.run.update({
      where: { id: runId },
      data: { status: 'running', pausedAt: null },
    });

    this.gateway.emitStatus(runId, 'running', run.currentStep);
    return true;
  }

  async cancelRun(runId: number) {
    const state = this.activeRuns.get(runId);
    if (!state) return false;

    const proc = state.process;
    if (proc.exitCode !== null) return false;

    state.cancelled = true;

    try {
      // Kill the entire process group
      if (proc.pid) {
        process.kill(-proc.pid, 'SIGTERM');
      }
    } catch {
      try {
        proc.kill('SIGTERM');
      } catch {
        // Process already dead
      }
    }

    return true;
  }

  getActiveRun(runId: number): ActiveRun | undefined {
    return this.activeRuns.get(runId);
  }

  hasActiveRun(): boolean {
    return this.activeRuns.size > 0;
  }

  getBufferedOutput(runId: number) {
    const state = this.activeRuns.get(runId);
    if (!state) return { lines: [], step: 0, command: null };
    return {
      lines: [...state.lines],
      step: state.currentStep,
      command: state.currentCommand,
    };
  }
}
