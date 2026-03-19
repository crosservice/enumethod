import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class RunsService {
  constructor(private prisma: PrismaService) {}

  async findAll(page = 1, limit = 20) {
    const skip = (page - 1) * limit;
    const [data, total] = await Promise.all([
      this.prisma.run.findMany({
        skip,
        take: limit,
        orderBy: { id: 'desc' },
        select: {
          id: true,
          targetIp: true,
          domain: true,
          status: true,
          currentStep: true,
          currentCommand: true,
          startedAt: true,
          finishedAt: true,
          createdById: true,
        },
      }),
      this.prisma.run.count(),
    ]);
    return { data, total, page, limit };
  }

  async findById(id: number) {
    const run = await this.prisma.run.findUnique({ where: { id } });
    if (!run) throw new NotFoundException('Run not found');
    return run;
  }

  async create(data: {
    targetIp: string;
    domain: string;
    arguments: Record<string, unknown>;
    outputDir: string;
    createdById: number;
  }) {
    return this.prisma.run.create({
      data: {
        targetIp: data.targetIp,
        domain: data.domain,
        arguments: data.arguments as any,
        outputDir: data.outputDir,
        status: 'running',
        startedAt: new Date(),
        createdById: data.createdById,
      },
    });
  }

  async update(id: number, data: Record<string, unknown>) {
    return this.prisma.run.update({ where: { id }, data });
  }

  async getOutputs(runId: number) {
    return this.prisma.runOutput.findMany({
      where: { runId },
      orderBy: { id: 'asc' },
    });
  }

  async createOutput(data: {
    runId: number;
    stepNumber: number;
    commandName: string;
    outputText: string;
    startedAt?: Date;
    finishedAt?: Date;
    exitCode?: number;
  }) {
    return this.prisma.runOutput.create({ data });
  }

  async appendOutput(id: number, text: string) {
    await this.prisma.runOutput.update({
      where: { id },
      data: {
        outputText: { set: undefined },
      },
    });
    // Use raw query to append text efficiently
    await this.prisma.$executeRaw`
      UPDATE run_outputs SET output_text = output_text || ${text} WHERE id = ${id}
    `;
  }

  async finishOutput(id: number, exitCode: number) {
    return this.prisma.runOutput.update({
      where: { id },
      data: { finishedAt: new Date(), exitCode },
    });
  }
}
