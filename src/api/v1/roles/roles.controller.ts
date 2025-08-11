import { Controller, Get, Post, Body, Patch, Param, Delete, Put, Query } from '@nestjs/common';
import { RolesService } from './roles.service';

import { RolesDto } from './dto/roles.dto';


@Controller('api/v1/roles')
export class RolesController {
  constructor(private readonly doctorService: RolesService) { }

  @Get('get-all-roles')
  findAll(): Promise<RolesDto[]> {
    return this.doctorService.findAllRoles();
  }



}
