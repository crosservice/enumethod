import { Module } from '@nestjs/common';
import { RunsService } from './runs.service';
import { RunsController } from './runs.controller';
import { RunManagerService } from './run-manager.service';
import { RunsGateway } from './runs.gateway';

@Module({
  providers: [RunsService, RunManagerService, RunsGateway],
  controllers: [RunsController],
  exports: [RunsService, RunManagerService],
})
export class RunsModule {}
