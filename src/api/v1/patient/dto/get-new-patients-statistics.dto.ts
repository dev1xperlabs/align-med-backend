import { IsInt, IsNumber, IsOptional, IsString } from 'class-validator';

export class GetNewPatientsStats {
    @IsInt()
    new_patients_today: number;

    @IsInt()
    new_patients_this_week: number;

    @IsInt()
    new_patients_this_month: number;

    @IsInt()
    new_patients_this_year: number;

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
