import { Controller, Get, Param, Res, NotFoundException } from '@nestjs/common';
import type { Response } from 'express';
import * as fs from 'fs';
import * as path from 'path';
import archiver from 'archiver';
import { PrismaService } from '../prisma/prisma.service';
import { ParseIntIdPipe } from '../common/pipes/parse-int-id.pipe';

@Controller('runs')
export class ReportsController {
  constructor(private prisma: PrismaService) {}

  @Get(':id/report')
  async getReport(@Param('id', ParseIntIdPipe) id: number, @Res() res: Response) {
    const run = await this.prisma.run.findUnique({ where: { id } });
    if (!run) throw new NotFoundException('Run not found');

    const reportPath = path.join(run.outputDir, 'report', 'report.html');
    if (!fs.existsSync(reportPath)) {
      throw new NotFoundException('Report not yet generated');
    }

    res.setHeader('Content-Type', 'text/html');
    fs.createReadStream(reportPath).pipe(res);
  }

  @Get(':id/export')
  async exportZip(@Param('id', ParseIntIdPipe) id: number, @Res() res: Response) {
    const run = await this.prisma.run.findUnique({ where: { id } });
    if (!run) throw new NotFoundException('Run not found');

    if (!fs.existsSync(run.outputDir)) {
      throw new NotFoundException('Output directory not found');
    }

    const safeTarget = run.targetIp.replace(/[^a-zA-Z0-9._-]/g, '_');
    const filename = `enumethod_${safeTarget}_run${id}.zip`;

    res.setHeader('Content-Type', 'application/zip');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

    const archive = archiver('zip', { zlib: { level: 9 } });
    archive.pipe(res);
    archive.directory(run.outputDir, path.basename(run.outputDir));
    archive.finalize();
  }
}
