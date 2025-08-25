import { BaseModel } from "../shared/base.model";

export class ForgetpasswordModel extends BaseModel {
    constructor(config?: Partial<BaseModel>) {
        super({
            tableName: 'forget_password_tokens',
            searchableColumns: ['id', 'token'],
            sortableColumns: ['id', 'created_at', 'updated_at'],
            filterableColumns: ['id'],
            defaultSortColumn: 'created_at',
            defaultSortOrder: 'DESC',
            defaultPageSize: 25,
            maxPageSize: 100,
            ...config
        });
    }
}