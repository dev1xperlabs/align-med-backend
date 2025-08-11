import { Transform } from 'class-transformer';
import { IsOptional, IsArray } from 'class-validator';
import { PaginationDto } from '../../globalDto/pagination.dto';

export class GetSumtOfNewPatientByAttorney extends PaginationDto {
    @IsOptional()
    @Transform(({ value }) => {
        if (Array.isArray(value)) return value.map(Number);
        if (typeof value === 'string') return [Number(value)];
        return [];
    })
    @IsArray()
    attorney_ids?: number[];
}




export class GetSumOfNewPatientByAttorneyResponse {
    getSumtOfNewPatientByAttorney: any[];
    totalRecords: number;
    currentPage: number;
}