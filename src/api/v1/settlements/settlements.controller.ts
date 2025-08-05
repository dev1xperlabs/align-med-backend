import { Controller, Get, Post, Body, Patch, Param, Delete, Query } from '@nestjs/common';
import { SettlementsService } from './settlements.service';
import { GetSettlementsByDate } from './dto/get-settlements-by-date.dto';
import { GetSettlementsByAttorneys } from './dto/get-settlements-by-attorneys.dto';
import { GetSettlementsStatistics } from './dto/get-settlements-stats.dto';

@Controller('api/v1/settlements')
export class SettlementsController {
  constructor(private readonly settlementsService: SettlementsService) { }



  @Post('get-settlements-by-date')
  async getSettlementsByDate(@Body() getSettlementsByDate: GetSettlementsByDate,): Promise<any[]> {
    return this.settlementsService.getSettlementsByDate(getSettlementsByDate);
  }

  @Post('get-settlements-by-attorneys')
  async getSettlementsByAttorneys(@Body() getSettlementsByAttorneys: GetSettlementsByAttorneys): Promise<any[]> {
    return this.settlementsService.getSettlementsByAttorneys(
      getSettlementsByAttorneys
    );
  }


  @Get('get-settlements-statistics')
  getSettlementsBillingSummary(): Promise<GetSettlementsStatistics> {
    return this.settlementsService.getSettlementsBilling();
  }


}
