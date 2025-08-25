// dtos/reset-password-request.dto.ts
import { IsEmail, IsNotEmpty, IsOptional } from 'class-validator';

export class ResetPasswordRequestDto {
  @IsEmail()
  @IsNotEmpty()
  recoveryEmail: string;

  @IsOptional()
  acessToken?: string;

  @IsOptional()
  message?: string;
}
