import { Injectable } from '@nestjs/common';
import * as bcrypt from 'bcrypt';
import { RegisterDto } from './dtos/register.dto';
import { DatabaseService } from '../../../database/database.service';
import { ResponseUserDto, User } from './interfaces/user.interface';
import { REFRESH_TOKEN_EXPIRATION_DAYS } from './constants';

@Injectable()
export class AuthRepository {
  constructor(private readonly databaseService: DatabaseService) {}

  async createUser(registerDto: RegisterDto): Promise<ResponseUserDto> {
    const hashedPassword = await bcrypt.hash(registerDto.password, 10);
    registerDto.status = "1";
    const { rows } = await this.databaseService.query(
      `INSERT INTO users(
        first_name, 
        last_name, 
        email, 
        password_hash, 
        phone_number, 
        status
     ) VALUES ($1, $2, $3, $4, $5, $6)
     RETURNING 
        id,
        first_name,
        last_name,
        email,
        phone_number,
        status,
        created_at,
        updated_at`,
      [
        registerDto.firstName,
        registerDto.lastName,
        registerDto.email,
        hashedPassword,
        registerDto.phoneNumber || null,
        registerDto.status,
      ],
    );
    return rows[0];
  }

  async findUserByEmail(email: string): Promise<User | null> {
    const { rows } = await this.databaseService.query(
      'SELECT * FROM users WHERE email = $1',
      [email],
    );
    return rows[0] || null;
  }

  async createRefreshToken(userId: number, token: string): Promise<void> {
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + REFRESH_TOKEN_EXPIRATION_DAYS);

    await this.databaseService.query(
      'INSERT INTO refresh_tokens (user_id, token, expires_at) VALUES ($1, $2, $3)',
      [userId, token, expiresAt],
    );
  }

  async findRefreshToken(
    token: string,
  ): Promise<{ user_id: number; expires_at: Date } | null> {
    const { rows } = await this.databaseService.query(
      'SELECT user_id, expires_at FROM refresh_tokens WHERE token = $1',
      [token],
    );
    return rows[0] || null;
  }

  async deleteRefreshToken(token: string): Promise<void> {
    await this.databaseService.query(
      'DELETE FROM refresh_tokens WHERE token = $1',
      [token],
    );
  }
}
