import { DatabaseService } from "../../../database/database.service";
import { BaseRepository } from "../shared/base.repository";
import { Injectable } from "@nestjs/common";

@Injectable()
export class SettlementsRepository extends BaseRepository {
    constructor(databaseService: DatabaseService) {
        super(databaseService, {
            tableName: 'settlements',
            searchableColumns: ['id', 'patient_id', 'attorney_id'],
            sortableColumns: ['id', 'patient_id', 'attorney_id', 'created_at', 'updated_at', 'settlement_percentage', 'settlement_amount'],
            filterableColumns: ['settlement_percentage', 'settlement_amount', 'attorney_id', 'patient_id'],
            defaultSortColumn: 'created_at',
            defaultSortOrder: 'DESC',
            defaultPageSize: 25,
            maxPageSize: 100,
        });
    }
}