import {
  IsDate,
  IsEmail,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
} from 'class-validator';

export class UpdateUserDto {
  @IsNumber()
  id: number;

  @IsString()
  first_name: string;

  @IsString()
  last_name: string;

  @IsOptional()
  @IsEmail()
  email?: string;

  @IsNumber()
  role_id: number;

  @IsOptional()
  status?: string;

  @IsString()
  updated_at: string;
}
