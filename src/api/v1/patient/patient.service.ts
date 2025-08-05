import { Injectable } from '@nestjs/common';
import { BaseService } from '../shared/base.service';
import { PatientRepository } from './patient.repository';
import { CreatePatientDto, UpdatePatientDto, Patient } from './patient.types';
import { PatientModel } from './patient.model';
import { formatDatePlus3Days, transformPatientCounts } from '../utils/helper';
import { GetSumOfNewPatientsByLocation, GetSumOfNewPatientsByLocationResponse } from './dto/get-sum-new-patients-by-location.dto';
import { GetCountOfNewPatientsByLocation, GetCountOfNewPatientsByLocationResponse } from './dto/get-count-new-patients-by-location.dto';
import { GetNewPatientsStats } from './dto/get-new-patients-statistics.dto';
import { PromiseWithChild } from 'child_process';

@Injectable()
export class PatientService extends BaseService<Patient> {
  constructor(private readonly patientRepository: PatientRepository) {
    super(patientRepository, new PatientModel());
  }

  async deactivatePatient(id: number): Promise<Patient | null> {
    return this.patientRepository.update(id, { status: false });
  }

  async activatePatient(id: number): Promise<Patient | null> {
    return this.patientRepository.update(id, { status: true });
  }

  async createPatient(createDto: CreatePatientDto): Promise<Patient> {
    const finalStatus = createDto.status === "1" ? '1' : '0';
    return this.patientRepository.create({
      ...createDto,
      status: finalStatus,
    });
  }

  async updatePatient(
    id: number,
    updateDto: UpdatePatientDto,
  ): Promise<Patient | null> {
    return this.patientRepository.update(id, {
      ...updateDto,
      updated_at: new Date(),
    });
  }

  async getSumOfNewPatientsByLocation(
    getSumOfNewPatientsByLocation: GetSumOfNewPatientsByLocation
  ): Promise<GetSumOfNewPatientsByLocationResponse[]> {
    const result = await this.patientRepository.callFunction<any>('get_sum_of_new_patients_by_location', [
      getSumOfNewPatientsByLocation.page_size,
      getSumOfNewPatientsByLocation.page_number,
      getSumOfNewPatientsByLocation.start_date,
      getSumOfNewPatientsByLocation.end_date,
    ]);


    if (!result || result.length === 0) {
      return [
        {

          getSumOfNewPatientsByLocation: [],
          totalRecords: 0,
          currentPage: getSumOfNewPatientsByLocation.page_number ?? 1,
        }
      ];
    }

    const transformedData = transformPatientCounts(result, true);

    return [{
      getSumOfNewPatientsByLocation: transformedData,
      totalRecords: Number(result[0].total_records ?? 0),
      currentPage: Number(getSumOfNewPatientsByLocation.page_number ?? 1),
    }
    ];

  }


  async getCountOfNewPatientsByLocation(
    getCountOfNewPatientsByLocation: GetCountOfNewPatientsByLocation
  ): Promise<GetCountOfNewPatientsByLocationResponse[]> {
    const result = await this.patientRepository.callFunction<any>(
      'get_count_of_new_patients_by_location',
      [
        getCountOfNewPatientsByLocation.page_size,
        getCountOfNewPatientsByLocation.page_number,
        getCountOfNewPatientsByLocation.start_date,
        getCountOfNewPatientsByLocation.end_date,
      ]
    );

    if (!result || result.length === 0) {
      return [
        {
          getCountOfNewPatientsByLocation: [],
          totalRecords: 0,
          currentPage: getCountOfNewPatientsByLocation.page_number ?? 1,
        },
      ];
    }

    const transformedData = transformPatientCounts(result, false);

    return [
      {
        getCountOfNewPatientsByLocation: transformedData,
        totalRecords: Number(result[0].total_records ?? 0),
        currentPage: Number(getCountOfNewPatientsByLocation.page_number ?? 1),
      },
    ];
  }





  async getPatientDataByYearFilter(): Promise<GetNewPatientsStats> {
    return await this.patientRepository.callFunction<GetNewPatientsStats>('get_new_patient_summary_test', []).then(res => res[0]);

  }


}
