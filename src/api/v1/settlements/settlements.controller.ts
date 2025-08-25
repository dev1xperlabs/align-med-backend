import { Controller, Get, Post, Body, Patch, Param, Delete, Query, UseGuards, HttpCode, HttpStatus } from '@nestjs/common';
import { SettlementsService } from './settlements.service';
import { GetSettlementsByDate } from './dto/get-settlements-by-date.dto';
import { GetSettlementsByAttorneys } from './dto/get-settlements-by-attorneys.dto';
import { GetSettlementsStatistics } from './dto/get-settlements-stats.dto';
import { AuthGuard } from '@nestjs/passport';

@Controller('api/v1/settlements')
export class SettlementsController {
  constructor(private readonly settlementsService: SettlementsService) { }



  @Post('get-settlements-by-date')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.CREATED)
  async getSettlementsByDate(@Body() getSettlementsByDate: GetSettlementsByDate,): Promise<any[]> {
    return this.settlementsService.getSettlementsByDate(getSettlementsByDate);
  }

  @Post('get-settlements-by-attorneys')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.CREATED)
  async getSettlementsByAttorneys(@Body() getSettlementsByAttorneys: GetSettlementsByAttorneys): Promise<any[]> {
    return this.settlementsService.getSettlementsByAttorneys(
      getSettlementsByAttorneys
    );
  }


  @Get('get-settlements-statistics')
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.OK)
  getSettlementsBillingSummary(): Promise<GetSettlementsStatistics> {
    return this.settlementsService.getSettlementsBilling();
  }


}
