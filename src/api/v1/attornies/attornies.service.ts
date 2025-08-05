import { Injectable } from '@nestjs/common';
import { AttorniesRepository } from './attornies.repository';
import { AttorniesModel } from './attornies.model';
import { BaseService } from '../shared/base.service';
import { formatDatePlus3Days, transformAttorneyData } from '../utils/helper';
import { GetCountOfNewPatientByAttorney, GetSumOfNewPatientByAttorneyResponse } from './dto/get-count-of-new-patient-by-attorney.dto';
import { GetSumtOfNewPatientByAttorney } from './dto/get-sum-of-new-patient-by-attorney.dto';
import { promises } from 'dns';
import { AttorneyDto } from './dto/attorney.dto';


@Injectable()
export class AttorniesService extends BaseService<AttorniesModel> {
  constructor(private readonly attorniesRepository: AttorniesRepository) {
    super(attorniesRepository, new AttorniesModel());
  }

  async findAllAttorneys(): Promise<AttorneyDto[]> {
    return this.attorniesRepository.findAll();
  }

  async getSumOfNewPatientByAttorney(
    getSumtOfNewPatientByAttorney: GetSumtOfNewPatientByAttorney
  ): Promise<GetSumOfNewPatientByAttorneyResponse[]> {
    const result = await this.attorniesRepository.callFunction<any>(
      'get_sum_of_billed_charges_by_attorney',
      [
        getSumtOfNewPatientByAttorney.attorney_ids,
        getSumtOfNewPatientByAttorney.page_size,
        getSumtOfNewPatientByAttorney.page_number,
        getSumtOfNewPatientByAttorney.start_date,
        getSumtOfNewPatientByAttorney.end_date,
      ]
    );

    if (!result || result.length === 0) {
      return [
        {
          getSumOfNewPatientByAttorney: [],
          totalRecords: 0,
          currentPage: getSumtOfNewPatientByAttorney.page_number ?? 1,
        },
      ];
    }

    const transformedData = transformAttorneyData(result, 'sum');

    return [
      {
        getSumOfNewPatientByAttorney: transformedData,
        totalRecords: Number(result[0].total_records ?? 0),
        currentPage: Number(result[0].current_page ?? 1),
      },
    ];
  }


  async getCountOfNewPatientByAttorney(
    getSumOfNewPatientByAttorney: GetSumtOfNewPatientByAttorney
  ): Promise<GetSumOfNewPatientByAttorneyResponse[]> {
    const result = await this.attorniesRepository.callFunction<any>(
      'get_count_of_patients_by_attorney',
      [
        getSumOfNewPatientByAttorney.attorney_ids,
        getSumOfNewPatientByAttorney.page_size,
        getSumOfNewPatientByAttorney.page_number,
        getSumOfNewPatientByAttorney.start_date,
        getSumOfNewPatientByAttorney.end_date,
      ],
    );

    if (!result || result.length === 0) {
      return [
        {
          getSumOfNewPatientByAttorney: [],
          totalRecords: 0,
          currentPage: getSumOfNewPatientByAttorney.page_number ?? 1,
        },
      ];
    }

    const transformedData = transformAttorneyData(result, 'count');

    return [
      {
        getSumOfNewPatientByAttorney: transformedData,
        totalRecords: Number(result[0].total_records ?? 0),
        currentPage: Number(getSumOfNewPatientByAttorney.page_number ?? 1),
      },
    ];
  }

}



