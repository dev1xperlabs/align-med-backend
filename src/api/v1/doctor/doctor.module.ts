import { Module } from '@nestjs/common';
import { DoctorService } from './doctor.service';
import { DoctorController } from './doctor.controller';
import { DatabaseModule } from '../../../database/database.module';
import { DoctorRepository } from './doctor.repository';
import { DatabaseService } from '../../../database/database.service';
import { ConfigService } from '@nestjs/config';

@Module({
  imports: [DatabaseModule],
  controllers: [DoctorController],
  providers: [DoctorService, DoctorRepository, DatabaseService, ConfigService],
})
export class DoctorModule { }
