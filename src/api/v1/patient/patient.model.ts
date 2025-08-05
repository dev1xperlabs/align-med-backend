import { BaseModel } from '../shared/base.model';

export class PatientModel extends BaseModel {
  constructor(config?: Partial<BaseModel>) {
    super({
      tableName: 'patients',
      searchableColumns: ['first_name', 'last_name', 'email', 'phone'],
      sortableColumns: [
        'id',
        'first_name',
        'last_name',
        'date_of_birth',
        'created_at',
      ],
      filterableColumns: ['gender', 'blood_type', 'status'],
      defaultPageSize: 25,
      maxPageSize: 100,
      ...config,
    });
  }
}
