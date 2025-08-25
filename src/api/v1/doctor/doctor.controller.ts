import { Controller, Get, Post, Body, Patch, Param, Delete, Put, Query, UseGuards, HttpCode, HttpStatus } from '@nestjs/common';
import { DoctorService } from './doctor.service';
import { CreateDoctorDto } from './dto/create-doctor.dto';
import { UpdateDoctorDto } from './dto/update-doctor.dto';
import { CalculateBonusDto } from './dto/calculate-bonus.dto';
import { DoctorDto } from './dto/doctor.dto';
import { AuthGuard } from '@nestjs/passport';

@Controller('api/v1/doctors')
export class DoctorController {
  constructor(private readonly doctorService: DoctorService) { }

  @Get("get-all-doctors")
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  findAll(): Promise<DoctorDto[]> {
    return this.doctorService.findAllDcotors();
  }

  @Post('calculate-bonus')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.CREATED)
  async getAttorneyBonusSummaryPost(
    @Body() calculateBonusDto: CalculateBonusDto,
  ): Promise<any[]> {
    return this.doctorService.getAttorneyBonusSummary(calculateBonusDto);
  }

}
