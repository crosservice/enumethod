import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { RunsService } from './runs.service';
import { RunsController } from './runs.controller';
import { RunManagerService } from './run-manager.service';
import { RunsGateway } from './runs.gateway';

@Module({
  imports: [JwtModule],
  providers: [RunsService, RunManagerService, RunsGateway],
  controllers: [RunsController],
  exports: [RunsService, RunManagerService],
})
export class RunsModule {}
