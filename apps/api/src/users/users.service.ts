import { Injectable, NotFoundException, ConflictException, ForbiddenException } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class UsersService {
  constructor(private prisma: PrismaService) {}

  async findAll() {
    const users = await this.prisma.user.findMany({
      select: {
        id: true,
        username: true,
        role: true,
        mustResetPassword: true,
        createdAt: true,
        updatedAt: true,
      },
      orderBy: { createdAt: 'desc' },
    });
    return users;
  }

  async findById(id: number) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      select: {
        id: true,
        username: true,
        role: true,
        mustResetPassword: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async create(username: string, password: string, role: string) {
    const existing = await this.prisma.user.findUnique({ where: { username } });
    if (existing) throw new ConflictException('Username already exists');

    const passwordHash = await bcrypt.hash(password, 10);
    return this.prisma.user.create({
      data: { username, passwordHash, role, mustResetPassword: true },
      select: {
        id: true,
        username: true,
        role: true,
        mustResetPassword: true,
        createdAt: true,
        updatedAt: true,
      },
    });
  }

  async update(id: number, data: { role?: string; password?: string }) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) throw new NotFoundException('User not found');

    const updateData: Record<string, unknown> = {};
    if (data.role) updateData.role = data.role;
    if (data.password) updateData.passwordHash = await bcrypt.hash(data.password, 10);

    return this.prisma.user.update({
      where: { id },
      data: updateData,
      select: {
        id: true,
        username: true,
        role: true,
        mustResetPassword: true,
        createdAt: true,
        updatedAt: true,
      },
    });
  }

  async delete(id: number) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) throw new NotFoundException('User not found');
    await this.prisma.user.delete({ where: { id } });
    return { deleted: true };
  }

  async changePassword(userId: number, currentPassword: string, newPassword: string) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');

    const valid = await bcrypt.compare(currentPassword, user.passwordHash);
    if (!valid) throw new ForbiddenException('Current password is incorrect');

    const passwordHash = await bcrypt.hash(newPassword, 10);
    await this.prisma.user.update({
      where: { id: userId },
      data: { passwordHash, mustResetPassword: false },
    });
    return { ok: true };
  }
}
