import { BaseModel } from "../shared/base.model";


export class AttorniesModel extends BaseModel {
    constructor(config?: Partial<BaseModel>) {
        super({
            tableName: "attornies",
            searchableColumns: ["name", "phone_number"],
            sortableColumns: ["id", "phone_number", "created_at"],
            filterableColumns: ["id", "email"],
            defaultPageSize: 25,
            maxPageSize: 100,
            ...config,
        });
    }
}