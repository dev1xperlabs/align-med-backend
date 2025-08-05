import { Test, TestingModule } from '@nestjs/testing';
import { RuleAttorneysMappingService } from './rule-attorneys-mapping.service';

describe('RuleAttorneysMappingService', () => {
  let service: RuleAttorneysMappingService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [RuleAttorneysMappingService],
    }).compile();

    service = module.get<RuleAttorneysMappingService>(RuleAttorneysMappingService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });
});
