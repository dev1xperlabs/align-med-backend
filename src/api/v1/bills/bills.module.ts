import { Module } from '@nestjs/common';
import { BillsService } from './bills.service';
import { BillsController } from './bills.controller';
import { DatabaseModule } from '../../../database/database.module';
import { BillsRepository } from './bills.repository';
import { DatabaseService } from '../../../database/database.service';
import { ConfigService } from '@nestjs/config';

@Module({
  imports: [DatabaseModule],
  controllers: [BillsController],
  providers: [BillsService, BillsRepository, DatabaseService, ConfigService],
})
export class BillsModule { }
