import { BaseModel } from "../shared/base.model";

export class DoctorModel extends BaseModel {
  constructor(config?: Partial<BaseModel>) {
    super({
      tableName: 'providers',
      searchableColumns: ['name', 'status'],
      sortableColumns: ['id', 'name', 'status', 'created_at', 'updated_at'],
      filterableColumns: ['status'],
      defaultPageSize: 25,
      maxPageSize: 100,
      ...config,
    });
  }
}