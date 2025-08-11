import { BaseModel } from "../shared/base.model";

export class UsersModel extends BaseModel {
    constructor(config?: Partial<BaseModel>) {
        super({
            tableName: 'users',
            searchableColumns: ['first_name', 'last_name', 'email'],
            sortableColumns: ['id', 'first_name', 'last_name', 'created_at', 'updated_at'],
            filterableColumns: ['role_id', 'id', 'status'],
            defaultSortColumn: 'created_at',
            defaultSortOrder: 'DESC',
            defaultPageSize: 25,
            maxPageSize: 100,
            ...config
        });
    }
}