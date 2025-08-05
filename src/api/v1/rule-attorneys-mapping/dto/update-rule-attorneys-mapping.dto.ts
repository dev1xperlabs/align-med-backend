import { PartialType } from '@nestjs/mapped-types';
import { CreateRuleAttorneysMappingDto } from './create-rule-attorneys-mapping.dto';

export class UpdateRuleAttorneysMappingDto extends PartialType(CreateRuleAttorneysMappingDto) {}
