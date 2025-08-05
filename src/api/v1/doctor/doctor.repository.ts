import { DatabaseService } from "../../../database/database.service";
import { BaseRepository } from "../shared/base.repository";
import { Injectable } from "@nestjs/common";

@Injectable()
export class DoctorRepository extends BaseRepository {
    constructor(databaseService: DatabaseService) {
        super(databaseService, {
            tableName: 'providers',
            searchableColumns: ['name', 'status'],
            sortableColumns: ['id', 'name', 'status', 'created_at', 'updated_at'],
            filterableColumns: ['status'],
            defaultSortColumn: 'created_at',
            defaultSortOrder: 'DESC',
            defaultPageSize: 25,
            maxPageSize: 100,
        });
    }
}