import { IsOptional, IsString, IsInt, IsArray, IsDateString } from 'class-validator';
import { Transform } from 'class-transformer';
import { PaginationDto } from '../../globalDto/pagination.dto';

export class GetSumOfNewPatientsByLocation extends PaginationDto { }



export class GetSumOfNewPatientsByLocationResponse {
    getSumOfNewPatientsByLocation: any[];
    totalRecords: number;
    currentPage: number;
}