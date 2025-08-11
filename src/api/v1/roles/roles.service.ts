import { Injectable, NotFoundException, InternalServerErrorException } from "@nestjs/common"
// import type { CreateRolesDto } from "./dto/create-roles.dto"
// import type { UpdateRolesDto } from "./dto/update-roles.dto"
// import { DatabaseService } from "../../../database/database.service"
// import { v4 as uuidv4 } from "uuid"
import { RolesRepository } from "./roles.repository"

import { BaseService } from "../shared/base.service"
import { RolesModel } from "./roles.model";
import { RolesDto } from "./dto/roles.dto";




@Injectable()
export class RolesService extends BaseService<RolesModel> {
  constructor(private readonly rolesrepository: RolesRepository) {
    super(rolesrepository, new RolesModel());
  }



  async findAllRoles(): Promise<RolesDto[]> {
    return this.rolesrepository.findAll();
  }




}
