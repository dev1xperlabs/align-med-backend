import { IsNumber, IsOptional, IsString } from 'class-validator';

export class GetCardsBillsCharges {
    @IsNumber()
    total_billed_today: number;

    @IsNumber()
    total_billed_this_week: number;

    @IsNumber()
    total_billed_this_month: number;

    @IsNumber()
    total_billed_this_year: number;

    @IsOptional()
    @IsNumber()
    percentage_today: number;

    @IsOptional()
    @IsNumber()
    percentage_week: number;

    @IsOptional()
    @IsNumber()
    percentage_month: number;

    @IsOptional()
    @IsNumber()
    percentage_year: number;

    @IsString()
    trend_today: string;

    @IsString()
    trend_week: string;

    @IsString()
    trend_month: string;

    @IsString()
    trend_year: string;
}
