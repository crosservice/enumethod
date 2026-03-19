import { Controller, Get, Post, Body, Param, Query, UseGuards, ConflictException } from '@nestjs/common';
import { RunsService } from './runs.service';
import { RunManagerService } from './run-manager.service';
import { CreateRunDto } from './dto/create-run.dto';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { ParseIntIdPipe } from '../common/pipes/parse-int-id.pipe';
import { ConfigService } from '@nestjs/config';
import * as path from 'path';

@Controller('runs')
export class RunsController {
  constructor(
    private runs: RunsService,
    private runManager: RunManagerService,
    private config: ConfigService,
  ) {}

  @Get()
  findAll(@Query('page') page?: string, @Query('limit') limit?: string) {
    return this.runs.findAll(
      page ? parseInt(page, 10) : 1,
      limit ? parseInt(limit, 10) : 20,
    );
  }

  @Get(':id')
  findOne(@Param('id', ParseIntIdPipe) id: number) {
    return this.runs.findById(id);
  }

  @Get(':id/outputs')
  getOutputs(@Param('id', ParseIntIdPipe) id: number) {
    return this.runs.getOutputs(id);
  }

  @Post()
  @UseGuards(RolesGuard)
  @Roles('admin')
  async create(@Body() dto: CreateRunDto, @CurrentUser('sub') userId: number) {
    if (this.runManager.hasActiveRun()) {
      throw new ConflictException('A scan is already running');
    }

    const runsDir = this.config.get('RUNS_DIR', '/opt/enumethod/runs');
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const safeTarget = dto.targetIp.replace(/[^a-zA-Z0-9._-]/g, '_');
    const outputDir = path.join(runsDir, `enum_${safeTarget}_${timestamp}`);

    const args = {
      domain: dto.domain || '',
      steps: dto.steps || 'all',
      timing: dto.timing ?? 4,
      skipUdp: dto.skipUdp || false,
      skipBruteforce: dto.skipBruteforce || false,
      dryRun: dto.dryRun || false,
      wordlist: dto.wordlist || '',
    };

    const run = await this.runs.create({
      targetIp: dto.targetIp,
      domain: dto.domain || '',
      arguments: args,
      outputDir,
      createdById: userId,
    });

    await this.runManager.startRun(run.id, dto.targetIp, args);
    return run;
  }

  @Post(':id/pause')
  @UseGuards(RolesGuard)
  @Roles('admin')
  async pause(@Param('id', ParseIntIdPipe) id: number) {
    const ok = await this.runManager.pauseRun(id);
    if (!ok) throw new ConflictException('Run is not active');
    return { ok: true };
  }

  @Post(':id/resume')
  @UseGuards(RolesGuard)
  @Roles('admin')
  async resume(@Param('id', ParseIntIdPipe) id: number) {
    const ok = await this.runManager.resumeRun(id);
    if (!ok) throw new ConflictException('Run is not paused');
    return { ok: true };
  }

  @Post(':id/cancel')
  @UseGuards(RolesGuard)
  @Roles('admin')
  async cancel(@Param('id', ParseIntIdPipe) id: number) {
    const ok = await this.runManager.cancelRun(id);
    if (!ok) throw new ConflictException('Run is not active');
    return { ok: true };
  }
}
