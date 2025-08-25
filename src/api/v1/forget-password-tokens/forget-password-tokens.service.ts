import {
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from '@nestjs/common';

import { ForgetpasswordRepository } from './forget-password-tokens.repository';
import { ForgetpasswordModel } from './forget-password-tokens.model';
import { BaseService } from '../shared/base.service';
import * as bcrypt from 'bcrypt';

import { ResponseUserDto } from '../auth/interfaces/user.interface';
import { UserRole } from '../auth/constants';
import { AuthRepository } from '../auth/auth.repository';
import { plainToInstance } from 'class-transformer';
import { CreateForgetPasswordTokensDto } from './dto/create-forget-password-tokens.dto';
import { ValidateAccessToken } from './dto/validate-token.dto';

@Injectable()
export class ForgetpasswordService extends BaseService<ForgetpasswordModel> {
  constructor(
    private readonly forgetpasswordRepository: ForgetpasswordRepository,
    private readonly authRepository: AuthRepository,
  ) {
    super(forgetpasswordRepository, new ForgetpasswordModel());
  }

  async createForgetPasswordToken(createForgetPasswordTokensDto: CreateForgetPasswordTokensDto): Promise<any> {
    return this.forgetpasswordRepository.create(createForgetPasswordTokensDto);
  }


  async validateAccessToken(validateAccessToken: ValidateAccessToken): Promise<boolean> {
    const tokenRecord = await this.forgetpasswordRepository.validateAccessToken(validateAccessToken.token);
    if (!tokenRecord) {
      return false;
    }
    return true;
  }



}
