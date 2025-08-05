import { DatabaseService } from "../../../database/database.service";
import { BaseRepository } from "../shared/base.repository";
import { Injectable } from "@nestjs/common";
@Injectable()
export class BillsRepository extends BaseRepository {
    constructor(databaseService: DatabaseService) {
        super(databaseService, {
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
        });
    }
}