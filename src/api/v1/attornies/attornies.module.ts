import { Module } from '@nestjs/common';
import { AttorniesService } from './attornies.service';
import { AttorniesController } from './attornies.controller';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../../../database/database.service';
import { AttorniesRepository } from './attornies.repository';

@Module({
  controllers: [AttorniesController],
  providers: [AttorniesService,
    ConfigService,
    DatabaseService,
    AttorniesRepository
  ],
})
export class AttorniesModule { }
