import { Injectable, NotFoundException, InternalServerErrorException } from "@nestjs/common"
// import type { CreateDoctorDto } from "./dto/create-doctor.dto"
// import type { UpdateDoctorDto } from "./dto/update-doctor.dto"
// import { DatabaseService } from "../../../database/database.service"
// import { v4 as uuidv4 } from "uuid"
import { DoctorRepository } from "./doctor.repository"
import { DoctorModel } from "./doctor.model"
import { BaseService } from "../shared/base.service"

import { formatBilledDateUTC } from "../utils/helper"
import { CalculateBonusDto } from "./dto/calculate-bonus.dto"
import { DoctorDto } from "./dto/doctor.dto"


@Injectable()
export class DoctorService extends BaseService<DoctorModel> {
  constructor(private readonly doctorrepository: DoctorRepository) {
    super(doctorrepository, new DoctorModel());
  }



  async findAllDcotors(): Promise<DoctorDto[]> {
    return this.doctorrepository.findAll();
  }


  getAttorneyBonusSummary(
    calculateBonusDto: CalculateBonusDto
  ): Promise<any[]> {
    return this.doctorrepository
      .callFunction<any>('get_attorney_bonus_summary', [
        calculateBonusDto.fromDate,
        calculateBonusDto.toDate,
        calculateBonusDto.rule_id,
      ])
  }


}
