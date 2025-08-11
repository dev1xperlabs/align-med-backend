import { Expose } from 'class-transformer';
import {
  IsEmail,
  IsOptional,
  IsString,
  IsIn,
  IsBoolean,
  IsNumber,
} from 'class-validator';
import { BaseEntity } from '../../shared/base.entity';

export class User extends BaseEntity {
  @IsNumber()
  id?: number;

  @Expose()
  @IsString()
  first_name: string;

  @Expose()
  @IsString()
  last_name: string;

  @Expose()
  @IsEmail()
  email: string;

  @Expose()
  @IsString()
  password: string;

  @Expose()
  @IsNumber()
  role_id: number;
}
