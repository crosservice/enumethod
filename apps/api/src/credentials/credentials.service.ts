import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CryptoService } from './crypto.service';

@Injectable()
export class CredentialsService {
  constructor(
    private prisma: PrismaService,
    private crypto: CryptoService,
  ) {}

  async findAll() {
    const creds = await this.prisma.credential.findMany({
      orderBy: { createdAt: 'desc' },
    });

    return creds.map((c) => {
      const decrypted = this.crypto.decrypt(c.encryptedKey, c.iv, c.authTag);
      const masked = '****' + decrypted.slice(-4);
      return {
        id: c.id,
        name: c.name,
        provider: c.provider,
        maskedKey: masked,
        createdAt: c.createdAt,
        updatedAt: c.updatedAt,
      };
    });
  }

  async create(name: string, provider: string, apiKey: string, userId: number) {
    const { encrypted, iv, authTag } = this.crypto.encrypt(apiKey);

    return this.prisma.credential.create({
      data: {
        name,
        provider,
        encryptedKey: encrypted,
        iv,
        authTag,
        createdById: userId,
      },
      select: {
        id: true,
        name: true,
        provider: true,
        createdAt: true,
        updatedAt: true,
      },
    });
  }

  async delete(id: number) {
    const cred = await this.prisma.credential.findUnique({ where: { id } });
    if (!cred) throw new NotFoundException('Credential not found');
    await this.prisma.credential.delete({ where: { id } });
    return { deleted: true };
  }

  async getDecryptedKey(provider: string): Promise<string | null> {
    const cred = await this.prisma.credential.findFirst({
      where: { provider },
      orderBy: { createdAt: 'desc' },
    });
    if (!cred) return null;
    return this.crypto.decrypt(cred.encryptedKey, cred.iv, cred.authTag);
  }
}
