import { PartialType } from '@nestjs/mapped-types';
import { CreateAttornyDto } from './create-attorny.dto';

export class UpdateAttornyDto extends PartialType(CreateAttornyDto) {}
