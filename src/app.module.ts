import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { DatabaseModule } from './database/database.module';
import { AuthModule } from './api/v1/auth/auth.module';
import { PatientModule } from './api/v1/patient/patient.module';
import { DatabaseService } from './database/database.service';
import { ConfigModule } from '@nestjs/config';
import { DoctorModule } from './api/v1/doctor/doctor.module';
import { AttorniesModule } from './api/v1/attornies/attornies.module';
import { SettlementsModule } from './api/v1/settlements/settlements.module';
import { BillsModule } from './api/v1/bills/bills.module';
import { RulesModule } from './api/v1/rules/rules.module';
import { RuleAttorneysMappingModule } from './api/v1/rule-attorneys-mapping/rule-attorneys-mapping.module';

@Module({
  imports: [ConfigModule.forRoot({
    isGlobal: true,
    envFilePath: '.env'
  }), DatabaseModule, AuthModule, PatientModule, DoctorModule, AttorniesModule, SettlementsModule, BillsModule, RulesModule, RuleAttorneysMappingModule],
  controllers: [AppController],
  providers: [AppService, DatabaseService],
})
export class AppModule { }
