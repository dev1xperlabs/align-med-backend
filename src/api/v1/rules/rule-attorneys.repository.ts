import { Injectable } from "@nestjs/common";
import { DatabaseService } from "../../../database/database.service";
import { BaseRepository } from "../shared/base.repository";

@Injectable()
export class RuleAttorneysRepository extends BaseRepository {
    constructor(databaseService: DatabaseService) {
        super(databaseService, {
            tableName: "rule_attorneys_mapping",
            searchableColumns: [],
            sortableColumns: ["rule_id", "attorney_id"],
            filterableColumns: ["rule_id", "attorney_id"],
            defaultSortColumn: "rule_id",
            defaultSortOrder: "ASC",
            defaultPageSize: 25,
            maxPageSize: 100,
        });
    }

    async bulkInsert(data: { rule_id: number; attorney_id: number }[]): Promise<void> {
        if (!data.length) return;

        const values = data
            .map(({ rule_id, attorney_id }) => `(${rule_id}, ${attorney_id})`)
            .join(", ");

        const sql = `INSERT INTO rule_attorneys_mapping (rule_id, attorney_id) VALUES ${values}`;
        await this.query(sql);
    }

    async findByRuleId(ruleId: string | number): Promise<{ attorney_id: number }[]> {
        const sql = `SELECT attorney_id FROM rule_attorneys_mapping WHERE rule_id = $1`;
        const result = await this.query(sql, [ruleId]);
        return result.rows;
    }

    async deleteByRuleId(ruleId: string | number): Promise<void> {
        const sql = `DELETE FROM rule_attorneys_mapping WHERE rule_id = $1`;
        await this.query(sql, [ruleId]);
    }
}
