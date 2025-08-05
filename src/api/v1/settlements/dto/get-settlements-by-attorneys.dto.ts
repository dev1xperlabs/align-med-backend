import {
    IsOptional,
    IsIn,
    IsInt,
    Min,
    IsDateString,
    IsArray,
    IsNumber,
} from 'class-validator';
import { Transform, Type } from 'class-transformer';
import { PaginationDto } from '../../globalDto/pagination.dto';


export class GetSettlementsByAttorneys extends PaginationDto {
    @IsOptional()
    @IsIn(['month', 'week', 'year'])
    group_by?: string;


    @IsOptional()
    @Transform(({ value }) => {
        if (Array.isArray(value)) return value.map((v) => parseInt(v, 10));
        if (typeof value === 'string') return [parseInt(value, 10)];
        return [];
    })
    @IsArray()
    @IsInt({ each: true })
    attorney_ids?: string[];
}
