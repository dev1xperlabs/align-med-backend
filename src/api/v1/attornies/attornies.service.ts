import { Injectable } from '@nestjs/common';
import { AttorniesRepository } from './attornies.repository';
import { AttorniesModel } from './attornies.model';
import { BaseService } from '../shared/base.service';
import { formatDatePlus3Days, isFullYearRange, transformAttorneyData } from '../utils/helper';
import { GetCountOfNewPatientByAttorney, GetCountOfNewPatientByAttorneyResponse } from './dto/get-count-of-new-patient-by-attorney.dto';
import { GetSumOfNewPatientByAttorneyResponse, GetSumtOfNewPatientByAttorney } from './dto/get-sum-of-new-patient-by-attorney.dto';
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


    const isYearRange = isFullYearRange(
      new Date(getSumtOfNewPatientByAttorney?.start_date ?? ''),
      new Date(getSumtOfNewPatientByAttorney?.end_date ?? '')
    );

    const functionName = isYearRange
      ? 'get_sum_of_billed_charges_by_attorney_weekly'
      : 'get_sum_of_billed_charges_by_attorney_daily';


    const result = await this.attorniesRepository.callFunction<any>(
      functionName,
      [
        getSumtOfNewPatientByAttorney.start_date,
        getSumtOfNewPatientByAttorney.end_date,
        getSumtOfNewPatientByAttorney.page_size,
        getSumtOfNewPatientByAttorney.page_number,
        getSumtOfNewPatientByAttorney.attorney_ids,
      ]
    );

    if (!result || result.length === 0) {
      return [
        {
          getSumtOfNewPatientByAttorney: [],
          totalRecords: 0,
          currentPage: getSumtOfNewPatientByAttorney.page_number ?? 1,
        },
      ];
    }

    const responseData = isYearRange ? result[0].get_sum_of_billed_charges_by_attorney_weekly : result[0].get_sum_of_billed_charges_by_attorney_daily


    return [
      {
        getSumtOfNewPatientByAttorney: responseData?.data,
        totalRecords: Number(responseData?.totalRecords ?? 0),
        currentPage: Number(getSumtOfNewPatientByAttorney.page_number ?? 1),
      },
    ];
  }


  async getCountOfNewPatientByAttorney(
    getCountOfNewPatientByAttorney: GetCountOfNewPatientByAttorney
  ): Promise<GetCountOfNewPatientByAttorneyResponse[]> {

    const isYearRange = isFullYearRange(
      new Date(getCountOfNewPatientByAttorney?.start_date ?? ''),
      new Date(getCountOfNewPatientByAttorney?.end_date ?? '')
    );

    const functionName = isYearRange
      ? 'get_count_of_new_patients_by_attorney_weekly'
      : 'get_count_of_new_patients_by_attorney_daily';

    const result = await this.attorniesRepository.callFunction<any>(
      functionName,
      [
        getCountOfNewPatientByAttorney.start_date,
        getCountOfNewPatientByAttorney.end_date,
        getCountOfNewPatientByAttorney.page_size,
        getCountOfNewPatientByAttorney.page_number,
        getCountOfNewPatientByAttorney.attorney_ids,

      ],
    );


    if (!result || result.length === 0) {
      return [
        {
          getCountOfNewPatientByAttorney: [],
          totalRecords: 0,
          currentPage: getCountOfNewPatientByAttorney.page_number ?? 1,
        },
      ];
    }
    const responseData = isYearRange ? result[0].get_count_of_new_patients_by_attorney_weekly : result[0].get_count_of_new_patients_by_attorney_daily
    const transformedData = transformAttorneyData(responseData.data);

    return [
      {
        getCountOfNewPatientByAttorney: transformedData,
        totalRecords: Number(responseData?.totalRecords ?? 0),
        currentPage: Number(getCountOfNewPatientByAttorney.page_number ?? 1),
      },
    ];
  }
}



