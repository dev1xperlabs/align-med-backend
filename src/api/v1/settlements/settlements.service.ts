import { Injectable } from '@nestjs/common';
import { CreateSettlementDto } from './dto/create-settlement.dto';
import { UpdateSettlementDto } from './dto/update-settlement.dto';
import { GetSettlementsByDate } from './dto/get-settlements-by-date.dto';
import { SettlementsModel } from './settlements.model';
import { SettlementsRepository } from './settlements.repository';

import { BaseService } from '../shared/base.service';
import { promises } from 'dns';
import { GetSettlementsByAttorneys } from './dto/get-settlements-by-attorneys.dto';
import { GetSettlementsStatistics } from './dto/get-settlements-stats.dto';
import { transformAttorneySettlementsData, transformSettlementSummaryData } from '../utils/helper';

@Injectable()
export class SettlementsService extends BaseService<SettlementsModel> {
  constructor(private readonly settlementsReporsitory: SettlementsRepository) {
    super(settlementsReporsitory, new SettlementsModel());
  }


  async getSettlementsByDate(
    getSettlementsByDate: GetSettlementsByDate
  ): Promise<any[]> {
    const result = await this.settlementsReporsitory.callFunction<any>('get_settlements_by_date', [
      getSettlementsByDate.group_by,
      getSettlementsByDate.page_size,
      getSettlementsByDate.page_number,
    ])


    console.log('result', result);
    if (!result || result.length === 0) {
      return [
        {

          data: [],
          totalRecords: 0,
          currentPage: getSettlementsByDate.page_number ?? 1,
        }
      ];
    }

    const transformedData = transformSettlementSummaryData(result);

    return [{
      data: transformedData,
      totalRecords: Number(result[0].total_records ?? 0),
      currentPage: Number(result[0].current_page ?? 1),
    }
    ];
  }

  async getSettlementsByAttorneys(
    getSettlementsByAttorneys: GetSettlementsByAttorneys

  ): Promise<any[]> {
    const result = await this.settlementsReporsitory.callFunction<any>('get_settlements_by_attorneys', [
      getSettlementsByAttorneys.attorney_ids,
      getSettlementsByAttorneys.group_by,
      getSettlementsByAttorneys.page_size,
      getSettlementsByAttorneys.page_number,
    ]);

    console.log('result', result);
    if (!result || result.length === 0) {
      return [
        {

          data: [],
          totalRecords: 0,
          currentPage: getSettlementsByAttorneys.page_number ?? 1,
        }
      ];
    }

    const transformedData = transformAttorneySettlementsData(result);

    return [{
      data: transformedData,
      totalRecords: Number(result[0].total_records ?? 0),
      currentPage: Number(result[0].current_page ?? 1),
    }
    ];
  }



  async getSettlementsBilling(): Promise<GetSettlementsStatistics> {
    const result = await this.settlementsReporsitory.callFunction<GetSettlementsStatistics>('get_settlements_billing_test', []);

    return result[0];
  }
}
