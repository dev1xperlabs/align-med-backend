import { Transform } from 'class-transformer';
import { IsOptional, IsArray, IsInt } from 'class-validator';
import { PaginationDto } from '../../globalDto/pagination.dto';

export class GetCountOfNewPatientByAttorney extends PaginationDto {

    @IsOptional()
    @Transform(({ value }) => {
        if (Array.isArray(value)) return value.map((v) => parseInt(v, 10));
        if (typeof value === 'string') return [parseInt(value, 10)];
        return [];
    })
    @IsArray()
    @IsInt({ each: true })
    attorney_ids?: number[];

}

export class GetCountOfNewPatientByAttorneyResponse {
    getCountOfNewPatientByAttorney: any[];
    totalRecords: number;
    currentPage: number;
}