import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as crypto from 'crypto';

@Injectable()
export class CryptoService {
  private readonly key: Buffer;

  constructor(private config: ConfigService) {
    const secret = config.get('ENCRYPTION_SECRET', 'dev-encryption-secret');
    // Derive a 256-bit key using PBKDF2
    this.key = crypto.pbkdf2Sync(secret, 'enumethod-vault-salt', 100000, 32, 'sha512');
  }

  encrypt(plaintext: string): { encrypted: string; iv: string; authTag: string } {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', this.key, iv);

    let encrypted = cipher.update(plaintext, 'utf8', 'hex');
    encrypted += cipher.final('hex');
    const authTag = cipher.getAuthTag().toString('hex');

    return {
      encrypted,
      iv: iv.toString('hex'),
      authTag,
    };
  }

  decrypt(encrypted: string, iv: string, authTag: string): string {
    const decipher = crypto.createDecipheriv(
      'aes-256-gcm',
      this.key,
      Buffer.from(iv, 'hex'),
    );
    decipher.setAuthTag(Buffer.from(authTag, 'hex'));

    let decrypted = decipher.update(encrypted, 'hex', 'utf8');
    decrypted += decipher.final('utf8');
    return decrypted;
  }
}
