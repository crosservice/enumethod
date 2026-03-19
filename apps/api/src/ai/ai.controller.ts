import { Controller, Post, Get, Param, Body, UseGuards } from '@nestjs/common';
import { AiService } from './ai.service';
import { TriggerAssessmentDto } from './dto/trigger-assessment.dto';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { ParseIntIdPipe } from '../common/pipes/parse-int-id.pipe';

@Controller('runs')
export class AiController {
  constructor(private ai: AiService) {}

  @Post(':id/assess')
  @UseGuards(RolesGuard)
  @Roles('admin')
  assess(
    @Param('id', ParseIntIdPipe) id: number,
    @Body() dto: TriggerAssessmentDto,
  ) {
    return this.ai.assess(id, dto.provider);
  }

  @Get(':id/assessment')
  getAssessment(@Param('id', ParseIntIdPipe) id: number) {
    return this.ai.getAssessment(id);
  }
}
