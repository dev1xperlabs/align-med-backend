import { IsEmail, IsNumber, IsString } from 'class-validator';

export class ResetPasswordDto {
  @IsNumber()
  user_id: number;

  password: string;
}
