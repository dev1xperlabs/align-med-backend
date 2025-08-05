import { IsOptional, IsString, IsInt, IsArray, IsDateString } from 'class-validator';
import { Transform } from 'class-transformer';
import { PaginationDto } from '../../globalDto/pagination.dto';

export class GetCountOfNewPatientsByLocation extends PaginationDto { }



export class GetCountOfNewPatientsByLocationResponse {
    getCountOfNewPatientsByLocation: any[];
    totalRecords: number;
    currentPage: number;
}