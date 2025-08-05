import { Injectable } from '@nestjs/common';
import { CreateRuleDto } from './dto/create-rule.dto';
import { UpdateRuleDto } from './dto/update-rule.dto';
import { RulesRepository } from './rules.repository';
import { RulesModel } from './rules.model';
import { BaseService } from '../shared/base.service';
import { RuleListDto } from './dto/get-all-rules.dto';
import { RuleEntity } from './entity/rule.entity';
import { RuleAttorneysMappingService } from '../rule-attorneys-mapping/rule-attorneys-mapping.service';




@Injectable()
export class RulesService extends BaseService<RulesModel> {
  constructor(
    private readonly rulesRepository: RulesRepository,
    private readonly ruleAttorneysMappingService: RuleAttorneysMappingService,
  ) {
    super(rulesRepository, new RulesModel());
  }

  async createRule(createRuleDto: CreateRuleDto): Promise<RuleEntity> {
    const { rule, rule_attorney_mapping } = createRuleDto;



    console.log(createRuleDto, "django")
    if (!rule) {
      throw new Error('Missing "rule" object in CreateRuleDto');
    }

    const createdRule = await this.rulesRepository.create(rule);

    if (rule_attorney_mapping?.length) {
      const inserts = rule_attorney_mapping.map((mapping) => ({
        rule_id: createdRule.id,
        attorney_id: mapping.attorney_id,
      }));

      await this.ruleAttorneysMappingService.bulkInsert(inserts);
    }

    return createdRule;
  }

  async findAll(): Promise<RuleListDto[]> {
    const rules = await this.rulesRepository.findAll();

    const rulesWithAttorneys = await Promise.all(
      rules.map(async (rule) => {
        const mappings = await this.ruleAttorneysMappingService.findByRuleId(rule.id);
        return {
          ...rule,
          attorney_ids: mappings.map((m) => m.attorney_id),
        };
      }),
    );

    return rulesWithAttorneys;
  }

  async findRuleById(id: string): Promise<RuleListDto> {
    const rule = await this.rulesRepository.findById(id);
    if (!rule) {
      throw new Error(`Rule with ID ${id} not found`);
    }

    const mappings = await this.ruleAttorneysMappingService.findByRuleId(id);

    return {
      ...rule,
      attorney_ids: mappings.map((m) => m.attorney_id),
    };
  }

  async updateRule(id: string, updateRuleDto: UpdateRuleDto): Promise<RuleEntity> {
    const { rule, rule_attorney_mapping = [] } = updateRuleDto;

    if (!rule) {
      throw new Error('Missing "rule" object in UpdateRuleDto');
    }

    rule.updated_at = new Date();

    const updatedRule = await this.rulesRepository.update(id, rule);

    await this.ruleAttorneysMappingService.deleteByRuleId(id);

    if (rule_attorney_mapping.length > 0) {
      const inserts = rule_attorney_mapping.map((mapping) => ({
        rule_id: Number(id),
        attorney_id: mapping.attorney_id,
      }));

      await this.ruleAttorneysMappingService.bulkInsert(inserts);
    }

    return {
      ...updatedRule,
      attorney_ids: rule_attorney_mapping.map((mapping) => mapping.attorney_id),
    };
  }


  async removeRule(id: string): Promise<{ deleted: boolean }> {
    await this.ruleAttorneysMappingService.deleteByRuleId(id);
    const result = await this.rulesRepository.delete(id);
    return { deleted: result };
  }
}
