import {
  IsEmail,
  IsString,
  MinLength,
  IsOptional,
  IsBoolean,
  IsPhoneNumber,
  MaxLength,
} from 'class-validator';

export class RegisterDto {
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  firstName: string;

  @IsString()
  @MinLength(2)
  @MaxLength(100)
  lastName: string;

  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  @MaxLength(100)
  password: string;

  @IsOptional()
  @IsPhoneNumber() // You can specify region if needed: @IsPhoneNumber('US')
  @MaxLength(20)
  phoneNumber?: string;

  @IsOptional()
  @IsBoolean()
  status?: string;
}
