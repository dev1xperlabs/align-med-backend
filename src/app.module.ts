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
import { UsersModule } from './api/v1/users/users.module';
import { RolesModule } from './api/v1/roles/roles.module';
import { ForgetpasswordModule } from './api/v1/forget-password-tokens/forget-password-tokens.module';


@Module({
  imports: [ConfigModule.forRoot({
    isGlobal: true,
    envFilePath: '.env'
  }), DatabaseModule, AuthModule, PatientModule, DoctorModule, AttorniesModule, SettlementsModule, BillsModule, RulesModule, RuleAttorneysMappingModule, UsersModule, RolesModule, ForgetpasswordModule],
  controllers: [AppController],
  providers: [AppService, DatabaseService],
})
export class AppModule { }
