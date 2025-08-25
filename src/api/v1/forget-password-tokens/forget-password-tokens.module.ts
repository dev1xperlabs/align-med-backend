import { Module } from '@nestjs/common';


import { ForgetpasswordRepository } from './forget-password-tokens.repository';
import { DatabaseModule } from '../../../database/database.module';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../../../database/database.service';
import { ForgetpasswordController } from './forget-password.controller';
import { AuthModule } from '../auth/auth.module';
import { ForgetpasswordService } from './forget-password-tokens.service';

@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [ForgetpasswordController,],
  providers: [ForgetpasswordService, DatabaseService, ConfigService, ForgetpasswordRepository],
  exports: [ForgetpasswordRepository]
})
export class ForgetpasswordModule { }
