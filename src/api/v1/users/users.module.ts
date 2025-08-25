import { Module } from '@nestjs/common';
import { UsersService } from './users.service';

import { UsersRepository } from './users.repository';
import { DatabaseModule } from '../../../database/database.module';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../../../database/database.service';
import { UsersController } from './users.controller';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [DatabaseModule, AuthModule],
  controllers: [UsersController,],
  providers: [UsersService, DatabaseService, ConfigService, UsersRepository],
  exports: [UsersRepository]
})
export class UsersModule { }
