import { Module } from '@nestjs/common';
import { AiService } from './ai.service';
import { AiController } from './ai.controller';
import { CveEnrichmentService } from './cve-enrichment.service';
import { CredentialsModule } from '../credentials/credentials.module';
import { SettingsModule } from '../settings/settings.module';

@Module({
  imports: [CredentialsModule, SettingsModule],
  providers: [AiService, CveEnrichmentService],
  controllers: [AiController],
})
export class AiModule {}
