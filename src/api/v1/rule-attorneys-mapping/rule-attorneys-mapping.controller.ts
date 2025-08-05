import { Controller, Get, Post, Body, Patch, Param, Delete } from '@nestjs/common';
import { RuleAttorneysMappingService } from './rule-attorneys-mapping.service';
import { CreateRuleAttorneysMappingDto } from './dto/create-rule-attorneys-mapping.dto';
import { UpdateRuleAttorneysMappingDto } from './dto/update-rule-attorneys-mapping.dto';

@Controller('rule-attorneys-mapping')
export class RuleAttorneysMappingController {
  constructor(private readonly ruleAttorneysMappingService: RuleAttorneysMappingService) { }


}
