import {

    IsString,
} from 'class-validator';

export class ValidateAccessToken {

    @IsString()
    token: string
}
