import { Module } from '@nestjs/common';
import { PatientController } from './patient.controller';
import { PatientService } from './patient.service';
import { PatientRepository } from './patient.repository';
import { DatabaseService } from '../../../database/database.service';
import { DatabaseModule } from '../../../database/database.module';
import { ConfigService } from '@nestjs/config';

@Module({
  imports: [DatabaseModule],
  providers: [
    ConfigService,
    DatabaseService, // Make sure DatabaseService is available
    PatientRepository,
    PatientService,
  ],
  controllers: [PatientController],
})
export class PatientModule { }
