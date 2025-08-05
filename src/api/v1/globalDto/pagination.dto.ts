import { Transform } from 'class-transformer';
import { IsOptional, IsArray } from 'class-validator';

export class PaginationDto {
    @Transform(({ value }) => parseInt(value, 10))
    @IsOptional()
    page_size?: number;

    @Transform(({ value }) => parseInt(value, 10))
    @IsOptional()
    page_number?: number;

    @IsOptional()
    start_date?: string;

    @IsOptional()
    end_date?: string;

    @IsOptional()
    total_records?: number;
}
