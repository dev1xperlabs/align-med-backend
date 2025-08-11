import { BaseModel } from "../shared/base.model";

export class RolesModel extends BaseModel {
  constructor(config?: Partial<BaseModel>) {
    super({
      tableName: 'roles',
      searchableColumns: ['id', 'name'],
      sortableColumns: ['id', 'name'],
      filterableColumns: ['id', 'name'],
      defaultPageSize: 25,
      maxPageSize: 100,
      ...config,
    });
  }
}