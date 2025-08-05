

export class RuleListDto {
    id: number;

    provider_id: number;

    bonus_percentage: string;

    status: string;

    created_at: Date;

    updated_at: Date;

    rule_name: string;

    attorney_ids: number[];
}
