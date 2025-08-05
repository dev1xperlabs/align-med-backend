import { Controller, Get, Post, Body, Patch, Param, Delete, Put, Query } from '@nestjs/common';
import { DoctorService } from './doctor.service';
import { CreateDoctorDto } from './dto/create-doctor.dto';
import { UpdateDoctorDto } from './dto/update-doctor.dto';
import { CalculateBonusDto } from './dto/calculate-bonus.dto';
import { DoctorDto } from './dto/doctor.dto';

@Controller('api/v1/doctors')
export class DoctorController {
  constructor(private readonly doctorService: DoctorService) { }

  @Get()
  findAll(): Promise<DoctorDto[]> {
    return this.doctorService.findAllDcotors();
  }

  @Post('calculate-bonus')
  async getAttorneyBonusSummaryPost(
    @Body() calculateBonusDto: CalculateBonusDto,
  ): Promise<any[]> {
    return this.doctorService.getAttorneyBonusSummary(calculateBonusDto);
  }

}
