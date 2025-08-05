import { IsNumber } from "class-validator";
import { BaseEntity } from "../../shared/base.entity";


export class RuleEntity extends BaseEntity {
    @IsNumber()
    id: number

    @IsNumber()
    provider_id: number

    @IsNumber()
    boonus_percentage: number

}