import { BaseModel } from "../shared/base.model";

export class BillsModel extends BaseModel {
    constructor(config?: Partial<BaseModel>) {
        super({
            tableName: 'bills',
            searchableColumns: ['description'],
            sortableColumns: [
                'id',
                'patient_id',
                'attorney_id',
                'location_id',
                'visit_date',
                'billed_date',
                'total_billed_charges',
                'status',
                'created_at',
                'updated_at'
            ],
            filterableColumns: [
                'id',
                'patient_id',
                'attorney_id',
                'location_id',
                'visit_date',
                'billed_date',
                'status',
                'created_at',
                'updated_at'
            ],
            defaultPageSize: 25,
            maxPageSize: 100,
            ...config,
        });

    }
}