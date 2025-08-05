import { Type } from 'class-transformer';
import { IsNumber, IsOptional } from 'class-validator';

export class BaseEntity {
    @IsNumber()
    @IsOptional()
    status: number;

    @Type(() => Date)
    created_at: Date;

    @Type(() => Date)
    updated_at: Date;

}
