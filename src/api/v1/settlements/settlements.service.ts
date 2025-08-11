import { Injectable } from '@nestjs/common';
import { GetSettlementsByDate } from './dto/get-settlements-by-date.dto';
import { SettlementsModel } from './settlements.model';
import { SettlementsRepository } from './settlements.repository';

import { BaseService } from '../shared/base.service';
import { GetSettlementsByAttorneys } from './dto/get-settlements-by-attorneys.dto';
import { GetSettlementsStatistics } from './dto/get-settlements-stats.dto';
import { isFullYearRange, transformAttorneySettlementsData, transformSettlementSummaryData } from '../utils/helper';

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

    const isYearRange = isFullYearRange(
      new Date(getSettlementsByAttorneys?.start_date ?? ''),
      new Date(getSettlementsByAttorneys?.end_date ?? '')
    );

    const functionName = isYearRange
      ? 'get_settlement_by_attorneys_weekly'
      : 'get_settlement_by_attorneys_daily';

    const result = await this.settlementsReporsitory.callFunction<any>(
      functionName,
      [
        getSettlementsByAttorneys.start_date,
        getSettlementsByAttorneys.end_date,
        getSettlementsByAttorneys.page_size,
        getSettlementsByAttorneys.page_number,
        getSettlementsByAttorneys.attorney_ids,
      ]);

    if (!result || result.length === 0) {
      return [
        {

          data: [],
          totalRecords: 0,
          currentPage: getSettlementsByAttorneys.page_number ?? 1,
        }
      ];
    }

    const responseData = isYearRange ? result[0].get_settlement_by_attorneys_weekly : result[0].get_settlement_by_attorneys_daily

    return [{
      data: responseData?.data,
      totalRecords: Number(responseData?.totalRecords ?? 0),
      currentPage: Number(getSettlementsByAttorneys.page_number ?? 1),
    }
    ];
  }



  async getSettlementsBilling(): Promise<GetSettlementsStatistics> {
    const result = await this.settlementsReporsitory.callFunction<GetSettlementsStatistics>('get_settlements_billing_test', []);
    return result[0];
  }
}
