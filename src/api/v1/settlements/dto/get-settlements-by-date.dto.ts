

import { IsOptional, IsIn, IsInt, Min, IsArray } from 'class-validator';
import { Transform, Type } from 'class-transformer';
import { PaginationDto } from '../../globalDto/pagination.dto';

export class GetSettlementsByDate extends PaginationDto {
    @IsOptional()
    @IsIn(['month', 'week', 'year'])
    group_by?: string;
}
