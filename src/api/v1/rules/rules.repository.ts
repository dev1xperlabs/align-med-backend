import { DatabaseService } from "../../../database/database.service";
import { BaseRepository } from "../shared/base.repository";
import { Injectable } from "@nestjs/common";

@Injectable()
export class RulesRepository extends BaseRepository {
    constructor(databaseService: DatabaseService) {
        super(databaseService, {
            tableName: 'rules',
            searchableColumns: ['bonus_percentage', 'status'],
            sortableColumns: ['id', 'provider_id', 'bonus_percentage', 'created_at', 'updated_at'],
            filterableColumns: ['provider_id', 'bonus_percentage', 'status'],
            defaultSortColumn: 'created_at',
            defaultSortOrder: 'DESC',
            defaultPageSize: 25,
            maxPageSize: 100,
        });
    }
}