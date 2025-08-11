import { Body, Controller, Get, HttpCode, HttpStatus, Post, Query, UseGuards } from '@nestjs/common';
import { GetCountOfNewPatientByAttorney } from './dto/get-count-of-new-patient-by-attorney.dto';
import { AuthGuard } from '@nestjs/passport';
import { ResultDto } from '../globalDto/result.dto';
import { AttorniesService } from './attornies.service';
import { GetSumtOfNewPatientByAttorney } from './dto/get-sum-of-new-patient-by-attorney.dto';
import { AttorneyDto } from './dto/attorney.dto';

@UseGuards(AuthGuard('jwt'))
@Controller('api/v1/attornies')
export class AttorniesController {
  constructor(private readonly attorniesService: AttorniesService) { }

  @Get()
  async findAll(): Promise<AttorneyDto[]> {
    return this.attorniesService.findAllAttorneys();
  }

  @Post('get-count-of-new-patient-by-attorney')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.CREATED)
  async getCountOfNewPatientByAttorney(
    @Body() getCountOfNewPatientByAttorney: GetCountOfNewPatientByAttorney
  ): Promise<any> {
    console.log('getCountOfNewPatientByAttorney', getCountOfNewPatientByAttorney);
    return this.attorniesService.getCountOfNewPatientByAttorney(getCountOfNewPatientByAttorney);
  }

  @Post('get-sum-of-new-patient-by-attorney')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.CREATED)
  async getSumOfNewPatientByAttorney(
    @Body() getSumtOfNewPatientByAttorney: GetSumtOfNewPatientByAttorney
  ): Promise<any[]> {
    return this.attorniesService.getSumOfNewPatientByAttorney(getSumtOfNewPatientByAttorney);
  }
}
