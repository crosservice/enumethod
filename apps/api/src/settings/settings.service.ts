import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class SettingsService {
  constructor(private prisma: PrismaService) {}

  async findAll() {
    return this.prisma.setting.findMany({
      select: { id: true, key: true, value: true, updatedAt: true },
      orderBy: { key: 'asc' },
    });
  }

  async findByKey(key: string) {
    const setting = await this.prisma.setting.findUnique({ where: { key } });
    if (!setting) throw new NotFoundException(`Setting "${key}" not found`);
    return setting;
  }

  async update(key: string, value: string, userId: number) {
    const setting = await this.prisma.setting.findUnique({ where: { key } });
    if (!setting) throw new NotFoundException(`Setting "${key}" not found`);

    return this.prisma.setting.update({
      where: { key },
      data: { value, updatedById: userId },
    });
  }
}
