import { BaseModel } from "../shared/base.model";



export class SettlementsModel extends BaseModel {
    constructor(config?: Partial<BaseModel>) {
        super({
            tableName: 'settlements',
            searchableColumns: ['id', 'patient_id', 'attorney_id'],
            sortableColumns: ['id', 'patient_id', 'attorney_id', 'created_at', 'updated_at', 'settlement_percentage', 'settlement_amount'],
            filterableColumns: ['settlement_percentage', 'settlement_amount', 'attorney_id', 'patient_id'],
            defaultSortColumn: 'created_at',
            defaultSortOrder: 'DESC',
            defaultPageSize: 25,
            maxPageSize: 100,
            ...config,
        });
    }
}
