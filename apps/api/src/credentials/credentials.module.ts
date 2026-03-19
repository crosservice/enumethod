import { Module } from '@nestjs/common';
import { CredentialsService } from './credentials.service';
import { CredentialsController } from './credentials.controller';
import { CryptoService } from './crypto.service';

@Module({
  providers: [CredentialsService, CryptoService],
  controllers: [CredentialsController],
  exports: [CredentialsService, CryptoService],
})
export class CredentialsModule {}
