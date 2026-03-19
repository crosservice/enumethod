import { IsString, MaxLength } from 'class-validator';

export class UpdateSettingDto {
  @IsString()
  @MaxLength(10000)
  value: string;
}
