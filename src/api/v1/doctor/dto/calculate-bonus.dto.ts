import { IsString, IsDateString, IsNumber } from 'class-validator';

export class CalculateBonusDto {
    @IsDateString()
    fromDate: string;

    @IsDateString()
    toDate: string;

    @IsNumber()
    rule_id: number;
}
