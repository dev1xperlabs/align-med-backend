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

export class ForgetPasswordTokensEntity extends BaseEntity {
  @IsString()
  token: string;
}
