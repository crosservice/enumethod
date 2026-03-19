import { IsString, IsIn } from 'class-validator';

export class TriggerAssessmentDto {
  @IsString()
  @IsIn(['claude', 'openai'])
  provider: 'claude' | 'openai';
}
