import { Controller, Get, Post, Body, Patch, Param, Delete, UseGuards, HttpStatus, HttpCode } from '@nestjs/common';
import { BillsService } from './bills.service';
import { CreateBillDto } from './dto/create-bill.dto';
import { UpdateBillDto } from './dto/update-bill.dto';
import { GetCardsBillsCharges } from './dto/get-cards-bills-charges.dto';
import { AuthGuard } from '@nestjs/passport';

@Controller('api/v1/bills')
export class BillsController {
  constructor(private readonly billsService: BillsService) { }

  @Post("get-bills-statistics")
  @UseGuards(AuthGuard('jwt'))
  @HttpCode(HttpStatus.CREATED)
  async getBillingSummary(): Promise<GetCardsBillsCharges> {
    return this.billsService.getBillingSummary();
  }
}
