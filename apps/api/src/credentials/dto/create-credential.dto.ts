import { IsString, IsIn, MaxLength, MinLength } from 'class-validator';

export class CreateCredentialDto {
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name: string;

  @IsString()
  @IsIn(['claude', 'openai'])
  provider: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  apiKey: string;
}
