import { IsNumber } from "class-validator"
import { BaseEntity } from "src/api/v1/shared/base.entity"

export class RuleAttorneysMapping extends BaseEntity {
    @IsNumber()
    id: number


    @IsNumber()
    rule_id: number


    @IsNumber()
    attorney_id: number

}
