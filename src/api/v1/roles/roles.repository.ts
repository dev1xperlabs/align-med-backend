import { DatabaseService } from "../../../database/database.service";
import { BaseRepository } from "../shared/base.repository";
import { Injectable } from "@nestjs/common";

@Injectable()
export class RolesRepository extends BaseRepository {
    constructor(databaseService: DatabaseService) {
        super(databaseService, {
            tableName: 'roles',
            searchableColumns: ['id', 'name'],
            sortableColumns: ['id', 'name', 'status'],
            filterableColumns: ['id, name'],
            defaultSortColumn: 'id',
            defaultSortOrder: 'DESC',
            defaultPageSize: 25,
            maxPageSize: 100,
        });
    }
}