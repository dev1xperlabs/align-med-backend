import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { Request } from 'express';
import { ResponseUserDto } from '../interfaces/user.interface';

export const CurrentUser = createParamDecorator(
  (data: unknown, ctx: ExecutionContext): ResponseUserDto => {
    const request = ctx.switchToHttp().getRequest<Request>();
    return request.user as ResponseUserDto;
  },
);
