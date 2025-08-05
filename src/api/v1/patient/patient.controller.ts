import {
  Controller,
  Get,
  Post,
  Put,
  Delete,
  Param,
  Body,
  Query,
  BadRequestException,
} from '@nestjs/common';
import { PatientService } from './patient.service';
import { CreatePatientDto, UpdatePatientDto } from './patient.types';
import { BaseListRequest } from '../shared/base-list.dto';
import { GetSumOfNewPatientsByLocation } from './dto/get-sum-new-patients-by-location.dto';
import { GetCountOfNewPatientsByLocation } from './dto/get-count-new-patients-by-location.dto';
import { GetNewPatientsStats } from './dto/get-new-patients-statistics.dto';

@Controller('api/v1/patients')
export class PatientController {
  constructor(private readonly patientService: PatientService) { }

  @Post()
  async create(@Body() createDto: CreatePatientDto) {
    return this.patientService.createPatient(createDto);
  }

  @Get()
  async findAll(@Query() request: BaseListRequest) {
    return this.patientService.list(request);
  }



  @Post('get-sum-of-new-patients-by-location')
  async getSumOfNewPatientsByLocation(
    @Body() getSumOfNewPatientsByLocation: GetSumOfNewPatientsByLocation,
  ): Promise<any> {

    return this.patientService.getSumOfNewPatientsByLocation(
      getSumOfNewPatientsByLocation
    );
  }

  @Post('get-count-of-new-patients-by-location')
  async getCountOfNewPatientsByLocation(@Body() getCountOfNewPatientsByLocation: GetCountOfNewPatientsByLocation): Promise<any[]> {
    return this.patientService.getCountOfNewPatientsByLocation(getCountOfNewPatientsByLocation);
  }


  @Post("get-new-patients-statistics")
  async getPatientDataByYearFilter(): Promise<GetNewPatientsStats> {
    return this.patientService.getPatientDataByYearFilter()
  }

  @Put(':id')
  async update(@Param('id') id: string, @Body() updateDto: UpdatePatientDto) {
    return this.patientService.updatePatient(parseInt(id), updateDto);
  }

  @Delete(':id')
  async remove(@Param('id') id: string) {
    return this.patientService.delete(parseInt(id));
  }

  @Put(':id/deactivate')
  async deactivate(@Param('id') id: string) {
    return this.patientService.deactivatePatient(parseInt(id));
  }

  @Put(':id/activate')
  async activate(@Param('id') id: string) {
    return this.patientService.activatePatient(parseInt(id));
  }



  @Get(':id')
  async findOne(@Param('id') id: string) {
    const parsedId = parseInt(id, 10);
    if (isNaN(parsedId)) {
      throw new BadRequestException('Invalid patient ID. Must be an integer.');
    }

    return this.patientService.findById(parsedId);
  }
}
