import {
  Controller,
  Get,
  Post,
  Body,
  Patch,
  Param,
  Delete,
  Put,
  UseGuards,
  HttpCode,
  HttpStatus,
  Req,
  HttpException,
} from '@nestjs/common';
import { ForgetpasswordService } from './forget-password-tokens.service';
import { CreateForgetPasswordTokensDto } from './dto/create-forget-password-tokens.dto';
import { ValidateAccessToken } from './dto/validate-token.dto';
import { Public } from '../auth/decorators/public.decorator';


@Controller('api/v1/forget-password')
export class ForgetpasswordController {
  constructor(private readonly forgetpasswordServiceService: ForgetpasswordService) { }

  @Public()
  @Post('validate-token')
  @HttpCode(HttpStatus.CREATED)
  async validateAccessToken(@Body() validateAccessToken: ValidateAccessToken): Promise<any> {
    return await this.forgetpasswordServiceService.validateAccessToken(validateAccessToken);
  }
}
