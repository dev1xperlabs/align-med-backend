import { Module } from '@nestjs/common';
import { RolesService } from './roles.service';
import { RolesController } from './roles.controller';
import { DatabaseModule } from '../../../database/database.module';
import { RolesRepository } from './roles.repository';
import { DatabaseService } from '../../../database/database.service';
import { ConfigService } from '@nestjs/config';

@Module({
  imports: [DatabaseModule],
  controllers: [RolesController],
  providers: [RolesService, RolesRepository, DatabaseService, ConfigService],
})
export class RolesModule { }
