import { Test, TestingModule } from '@nestjs/testing';
import { AttorniesService } from './attornies.service';

describe('AttorniesService', () => {
  let service: AttorniesService;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [AttorniesService],
    }).compile();

    service = module.get<AttorniesService>(AttorniesService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });
});
