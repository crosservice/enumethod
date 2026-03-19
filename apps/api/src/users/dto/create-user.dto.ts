import { IsString, MinLength, MaxLength, IsIn } from 'class-validator';

export class CreateUserDto {
  @IsString()
  @MinLength(3)
  @MaxLength(64)
  username: string;

  @IsString()
  @MinLength(8)
  @MaxLength(128)
  password: string;

  @IsString()
  @IsIn(['admin', 'view'])
  role: string;
}
