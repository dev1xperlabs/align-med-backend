import { Injectable } from '@nestjs/common';
import { CreateBillDto } from './dto/create-bill.dto';
import { UpdateBillDto } from './dto/update-bill.dto';
import { BaseService } from '../shared/base.service';
import { BillsRepository } from './bills.repository';
import { BillsModel } from './bills.model';
import { GetCardsBillsCharges } from './dto/get-cards-bills-charges.dto';


@Injectable()
export class BillsService extends BaseService<BillsModel> {
  constructor(private readonly billsRepository: BillsRepository) {
    super(billsRepository, new BillsModel());
  }



  async getBillingSummary(): Promise<GetCardsBillsCharges> {
    return this.billsRepository.callFunction<GetCardsBillsCharges>('get_billing_summary', []).then(res => res[0]);
  }
}
