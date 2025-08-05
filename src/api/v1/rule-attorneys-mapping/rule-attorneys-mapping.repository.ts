import { Injectable } from "@nestjs/common";
import { BaseRepository } from "../shared/base.repository";
import { DatabaseService } from "../../../database/database.service";


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


}
