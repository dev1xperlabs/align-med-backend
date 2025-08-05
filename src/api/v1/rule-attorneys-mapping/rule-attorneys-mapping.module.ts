import { Module } from '@nestjs/common';
import { RuleAttorneysMappingService } from './rule-attorneys-mapping.service';
import { RuleAttorneysMappingController } from './rule-attorneys-mapping.controller';
import { DatabaseModule } from '../../../database/database.module';
import { RuleAttorneysRepository } from './rule-attorneys-mapping.repository';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../../../database/database.service';

@Module({
  imports: [DatabaseModule],
  controllers: [RuleAttorneysMappingController],
  providers: [
    RuleAttorneysMappingService,
    DatabaseService,
    ConfigService,
    RuleAttorneysRepository
  ],
  exports: [RuleAttorneysMappingService],
})
export class RuleAttorneysMappingModule { }
