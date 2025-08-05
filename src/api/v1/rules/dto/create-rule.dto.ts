import { RuleAttorneysMapping } from '../../rule-attorneys-mapping/entities/rule-attorneys-mapping.entity';
import { RuleEntity } from '../entity/rule.entity';

export class CreateRuleDto {
    rule: RuleEntity


    rule_attorney_mapping: RuleAttorneysMapping[]
}
