import { IsString, IsOptional, IsBoolean, IsInt, Min, Max, Matches, MaxLength } from 'class-validator';

export class CreateRunDto {
  @IsString()
  @MaxLength(255)
  @Matches(/^(\d{1,3}\.){3}\d{1,3}$|^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$|^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$/, {
    message: 'Invalid target IP or hostname',
  })
  targetIp: string;

  @IsOptional()
  @IsString()
  @MaxLength(255)
  domain?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  steps?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(5)
  timing?: number;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  wordlist?: string;

  @IsOptional()
  @IsBoolean()
  skipUdp?: boolean;

  @IsOptional()
  @IsBoolean()
  skipBruteforce?: boolean;

  @IsOptional()
  @IsBoolean()
  dryRun?: boolean;
}
