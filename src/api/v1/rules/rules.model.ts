import { BaseModel } from "../shared/base.model";

export class RulesModel extends BaseModel {
    constructor(config?: Partial<BaseModel>) {
        super({
            tableName: 'rules',
            searchableColumns: ['bonus_percentage', 'status'],
            sortableColumns: ['id', 'provider_id', 'bonus_percentage', 'created_at', 'updated_at'],
            filterableColumns: ['provider_id', 'bonus_percentage', 'status'],
            defaultSortColumn: 'created_at',
            defaultSortOrder: 'DESC',
            defaultPageSize: 25,
            maxPageSize: 100,
            ...config
        });
    }
}