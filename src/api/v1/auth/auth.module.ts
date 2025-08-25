import { Module } from '@nestjs/common';
import { DatabaseModule } from '../../../database/database.module';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { JwtStrategy } from './strategies/jwt.strategy';
import { PassportModule } from '@nestjs/passport';
import { AuthRepository } from './auth.repository';
import { UsersRepository } from '../users/users.repository';
import { ForgetpasswordRepository } from '../forget-password-tokens/forget-password-tokens.repository';

@Module({
  imports: [
    DatabaseModule,
    PassportModule.register({ defaultStrategy: 'jwt' }),
  ],
  providers: [AuthService, JwtStrategy, AuthRepository, UsersRepository, ForgetpasswordRepository],
  controllers: [AuthController],
  exports: [JwtStrategy, PassportModule, AuthRepository],
})
export class AuthModule { }
