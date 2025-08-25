import {

  IsString,
} from 'class-validator';

export class CreateForgetPasswordTokensDto {

  @IsString()
  token: string
}
