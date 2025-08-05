import { Test, TestingModule } from '@nestjs/testing';
import { AttorniesController } from './attornies.controller';
import { AttorniesService } from './attornies.service';

describe('AttorniesController', () => {
  let controller: AttorniesController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [AttorniesController],
      providers: [AttorniesService],
    }).compile();

    controller = module.get<AttorniesController>(AttorniesController);
  });

  it('should be defined', () => {
    expect(controller).toBeDefined();
  });
});
