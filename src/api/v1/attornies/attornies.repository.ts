import { DatabaseService } from '../../../database/database.service';
import { BaseRepository } from '../shared/base.repository';
import { Injectable } from '@nestjs/common';

@Injectable()
export class AttorniesRepository extends BaseRepository {
    constructor(databaseService: DatabaseService) {
        super(databaseService, {
            tableName: 'attornies',
            searchableColumns: ['name', 'phone_number'],
            sortableColumns: ['id', 'phone_number', 'created_at'],
            filterableColumns: ['id', 'email'],
            defaultSortColumn: 'created_at',
            defaultSortOrder: 'DESC',
            defaultPageSize: 25,
            maxPageSize: 100,
        });
    }
}