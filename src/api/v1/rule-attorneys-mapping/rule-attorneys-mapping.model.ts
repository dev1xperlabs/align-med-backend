import { BaseModel } from "../shared/base.model";


export class RuleAttorneysMappingModel extends BaseModel {
    constructor(config?: Partial<BaseModel>) {
        super({
            tableName: "rule_attorneys_mapping",
            searchableColumns: [],
            sortableColumns: ["rule_id", "attorney_id"],
            filterableColumns: ["rule_id", "attorney_id"],
            defaultSortColumn: "rule_id",
            defaultSortOrder: "ASC",
            defaultPageSize: 25,
            maxPageSize: 100,
            ...config
        });
    }
}