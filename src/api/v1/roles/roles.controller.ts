import { Controller, Get, Post, Body, Patch, Param, Delete, Put, Query, UseGuards, HttpStatus, HttpCode } from '@nestjs/common';
import { RolesService } from './roles.service';

import { RolesDto } from './dto/roles.dto';
import { AuthGuard } from '@nestjs/passport';


@Controller('api/v1/roles')
export class RolesController {
  constructor(private readonly doctorService: RolesService) { }

  @Get('get-all-roles')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  findAll(): Promise<RolesDto[]> {
    return this.doctorService.findAllRoles();
  }



}
