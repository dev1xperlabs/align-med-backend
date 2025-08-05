import { Injectable } from '@nestjs/common';
import { RuleAttorneysRepository } from './rule-attorneys-mapping.repository';
import { RuleAttorneysMappingModel } from './rule-attorneys-mapping.model';
import { BaseService } from '../shared/base.service';

@Injectable()
export class RuleAttorneysMappingService extends BaseService<RuleAttorneysMappingModel> {
  constructor(
    private readonly ruleAttorneysRepository: RuleAttorneysRepository,
  ) {
    super(ruleAttorneysRepository, new RuleAttorneysMappingModel());
  }

  async bulkInsert(mappings: { rule_id: number; attorney_id: number }[]): Promise<void> {
    if (!mappings.length) return;

    for (const { rule_id, attorney_id } of mappings) {
      const sql = `INSERT INTO rule_attorneys_mapping (rule_id, attorney_id) VALUES ($1, $2)`;
      await this.ruleAttorneysRepository.query(sql, [rule_id, attorney_id]);
    }
  }

  async findByRuleId(ruleId: string | number): Promise<{ attorney_id: number }[]> {
    const sql = `SELECT attorney_id FROM rule_attorneys_mapping WHERE rule_id = $1`;
    const result = await this.ruleAttorneysRepository.query(sql, [ruleId]);
    return result.rows;
  }

  async deleteByRuleId(ruleId: string | number): Promise<void> {
    const sql = `DELETE FROM rule_attorneys_mapping WHERE rule_id = $1`;
    await this.ruleAttorneysRepository.query(sql, [ruleId]);
  }
}
