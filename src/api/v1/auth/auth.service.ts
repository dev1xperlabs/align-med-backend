import { Injectable, UnauthorizedException } from '@nestjs/common';
import * as jwt from 'jsonwebtoken';
import * as bcrypt from 'bcrypt';
import { AuthRepository } from './auth.repository';
import { RegisterDto } from './dtos/register.dto';
import { LoginDto } from './dtos/login.dto';
import { User, ResponseUserDto } from './interfaces/user.interface';
import { TokenPayload } from './interfaces/token-payload.interface';
import {
  JWT_SECRET,
  JWT_EXPIRATION,
  REFRESH_TOKEN_EXPIRATION_DAYS,
} from './constants';

@Injectable()
export class AuthService {
  constructor(private readonly authRepository: AuthRepository) { }

  async register(registerDto: RegisterDto): Promise<ResponseUserDto> {


    const existingUser = await this.authRepository.findUserByEmail(
      registerDto.email,
    );
    if (existingUser) {
      throw new UnauthorizedException('Email already exists');
    }

    return this.authRepository.createUser(registerDto);
  }

  async login(
    loginDto: LoginDto,
  ): Promise<{
    user: ResponseUserDto;
    accessToken: string;
    refreshToken: string;
  }> {
    const user = await this.validateUser(loginDto);
    if (!user) {
      throw new UnauthorizedException('Invalid credentials');
    }

    // Generate tokens
    const accessToken = this.generateAccessToken(user);
    const refreshToken = jwt.sign({ userId: user.id }, JWT_SECRET, {
      expiresIn: `${REFRESH_TOKEN_EXPIRATION_DAYS}d`,
    });

    // Store refresh token
    await this.authRepository.createRefreshToken(user.id, refreshToken);

    // Create response user object without password
    const responseUser: ResponseUserDto = {
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      created_at: user.created_at,
      updated_at: user.updated_at,
    };

    return {
      user: responseUser,
      accessToken,
      refreshToken,
    };
  }

  async refreshToken(refreshToken: string): Promise<{ accessToken: string }> {
    const tokenData = await this.authRepository.findRefreshToken(refreshToken);
    if (!tokenData) {
      throw new UnauthorizedException('Invalid refresh token');
    }

    if (new Date() > tokenData.expires_at) {
      await this.authRepository.deleteRefreshToken(refreshToken);
      throw new UnauthorizedException('Refresh token expired');
    }

    const accessToken = this.generateAccessToken({
      id: tokenData.user_id,
    } as User);
    return { accessToken };
  }

  async logout(refreshToken: string): Promise<void> {
    await this.authRepository.deleteRefreshToken(refreshToken);
  }

  private generateAccessToken(user: User): string {
    const payload: TokenPayload = { userId: user.id };
    return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRATION });
  }

  private async validateUser(loginDto: LoginDto): Promise<User | null> {
    const user = await this.authRepository.findUserByEmail(loginDto.email);
    if (!user) return null;

    const isPasswordValid = await bcrypt.compare(
      loginDto.password,
      user.password_hash,
    );
    return isPasswordValid ? user : null;
  }
}
