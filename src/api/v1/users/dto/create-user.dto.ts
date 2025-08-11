import {
  IsEmail,
  IsOptional,
  IsString,
  IsIn,
  IsBoolean,
  IsNumber,
} from 'class-validator';

export class CreateUserDto {
  @IsString()
  first_name: string;

  @IsString()
  last_name: string;

  @IsEmail()
  email: string;

  @IsString()
  password: string;

  @IsNumber()
  role_id: number;

  @IsOptional()
  status: string;

  @IsString()
  created_at: Date;

  @IsString()
  updated_at: Date;
}
