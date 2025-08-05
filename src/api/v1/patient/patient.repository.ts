import { DatabaseService } from '../../../database/database.service';
import { BaseRepository } from '../shared/base.repository';
import { Injectable } from '@nestjs/common';

@Injectable()
export class PatientRepository extends BaseRepository {
  constructor(databaseService: DatabaseService) {
    super(databaseService, {
      tableName: 'patients',
      searchableColumns: ['first_name', 'last_name', 'email', 'phone'],
      sortableColumns: ['id', 'first_name', 'last_name', 'created_at'],
      filterableColumns: ['gender', 'blood_type', 'is_active'],
      defaultSortColumn: 'created_at',
      defaultSortOrder: 'DESC',
      defaultPageSize: 25,
      maxPageSize: 100,
    });
  }
}
