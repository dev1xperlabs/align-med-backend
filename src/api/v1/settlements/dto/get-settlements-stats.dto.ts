import { IsOptional, IsNumber, IsString } from 'class-validator';

export class GetSettlementsStatistics {
    @IsString()
    total_billed_today: string;

    @IsString()
    total_billed_this_week: string;

    @IsString()
    total_billed_this_month: string;

    @IsString()
    total_billed_this_year: string;

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
