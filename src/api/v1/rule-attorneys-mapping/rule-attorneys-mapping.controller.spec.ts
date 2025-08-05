import { Test, TestingModule } from '@nestjs/testing';
import { RuleAttorneysMappingController } from './rule-attorneys-mapping.controller';
import { RuleAttorneysMappingService } from './rule-attorneys-mapping.service';

describe('RuleAttorneysMappingController', () => {
  let controller: RuleAttorneysMappingController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [RuleAttorneysMappingController],
      providers: [RuleAttorneysMappingService],
    }).compile();

    controller = module.get<RuleAttorneysMappingController>(RuleAttorneysMappingController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });
});
