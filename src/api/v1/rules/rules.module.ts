import { Module } from '@nestjs/common';
import { RulesService } from './rules.service';
import { RulesController } from './rules.controller';
import { RulesRepository } from './rules.repository';
import { DatabaseModule } from '../../../database/database.module';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../../../database/database.service';
import { RuleAttorneysRepository } from './rule-attorneys.repository';
import { RuleAttorneysMappingModule } from '../rule-attorneys-mapping/rule-attorneys-mapping.module';

@Module({
  imports: [DatabaseModule, RuleAttorneysMappingModule],
  controllers: [RulesController,],
  providers: [RulesService, DatabaseService, ConfigService, RulesRepository, RuleAttorneysRepository],
})
export class RulesModule { }
