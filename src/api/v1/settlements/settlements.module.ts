import { Module } from '@nestjs/common';
import { SettlementsService } from './settlements.service';
import { SettlementsController } from './settlements.controller';
import { DatabaseService } from '../../../database/database.service';
import { ConfigService } from '@nestjs/config';
import { DatabaseModule } from '../../../database/database.module';
import { SettlementsRepository } from './settlements.repository';

@Module({
  imports: [DatabaseModule],
  controllers: [SettlementsController],
  providers: [SettlementsService, DatabaseService, ConfigService, SettlementsRepository],
})
export class SettlementsModule { }

