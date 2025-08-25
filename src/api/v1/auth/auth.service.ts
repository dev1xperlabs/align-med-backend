import {
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';
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
import { ResetPasswordRequestDto } from './dtos/request-reset-password.dto';
import {
  JwtPayloadWithUserId,
  ResetPasswordDto,
} from './interfaces/reset-password.interface';
import { UsersRepository } from '../users/users.repository';
import { ForgetpasswordRepository } from '../forget-password-tokens/forget-password-tokens.repository';

@Injectable()
export class AuthService {
  constructor(
    private readonly authRepository: AuthRepository,
    private readonly usersRepository: UsersRepository,
    private readonly forgetpasswordRepository: ForgetpasswordRepository,
  ) {}

  async register(registerDto: RegisterDto): Promise<ResponseUserDto> {
    const existingUser = await this.authRepository.findUserByEmail(
      registerDto.email,
    );
    if (existingUser) {
      throw new UnauthorizedException('Email already exists');
    }

    return this.authRepository.createUser(registerDto);
  }

  async login(loginDto: LoginDto): Promise<{
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
      role_id: user.role_id,
      created_at: user.created_at,
      updated_at: user.updated_at,
    };

    return {
      user: responseUser,
      accessToken,
      refreshToken,
    };
  }

  async requestPasswordReset(
    resetPasswordRequestDto: ResetPasswordRequestDto,
  ): Promise<ResetPasswordRequestDto> {
    const user = await this.authRepository.findUserByEmail(
      resetPasswordRequestDto.recoveryEmail,
    );
    if (!user) {
      throw new NotFoundException('No account found with this email');
    }
    const token = this.generateAccessToken(user, 1);

    await this.forgetpasswordRepository.createForgetPasswordToken(token);

    return {
      recoveryEmail: resetPasswordRequestDto.recoveryEmail,
      message: 'Password reset email sent',
      acessToken: token,
    };
  }

  // ----------------------- Reset passowrd function
  async resetpassword(resetPasswordDto: ResetPasswordDto): Promise<void> {
    const { access_token, password } = resetPasswordDto;

    try {
      const payload = jwt.verify(
        access_token,
        JWT_SECRET,
      ) as JwtPayloadWithUserId;

      const userId = payload?.userId;

      if (!userId) {
        throw new Error('Invalid token payload: userId missing');
      }

      const user = await this.usersRepository.findById(userId);
      if (!user) {
        throw new NotFoundException('User not found');
      }

      user.password = await bcrypt.hash(password, 10);
      user.updated_at = new Date();

      console.log(access_token, 'token is auth service');
      await this.forgetpasswordRepository.deleteTokenByToken(access_token);

      return this.usersRepository.update(user.id, user);
    } catch (err) {
      throw new UnauthorizedException('Invalid or expired token');
    }
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

  private generateAccessToken(
    user: User,
    token_expiration: number = JWT_EXPIRATION,
  ): string {
    const payload: TokenPayload = { userId: user.id };
    return jwt.sign(payload, JWT_SECRET, { expiresIn: `${token_expiration}h` });
  }

  private async validateUser(loginDto: LoginDto): Promise<User | null> {
    const user = await this.authRepository.findUserByEmail(loginDto.email);

    if (!user) return null;

    const isPasswordValid = await bcrypt.compare(
      loginDto.password,
      user.password,
    );
    return isPasswordValid ? user : null;
  }
}
