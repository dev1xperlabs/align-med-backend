import { IsEmail, IsNumber, IsString } from 'class-validator';
import jwt from 'jsonwebtoken';

export class ResetPasswordDto {
    access_token: string;

    password: string;
}

export interface JwtPayloadWithUserId extends jwt.JwtPayload {
    userId: string;
}
