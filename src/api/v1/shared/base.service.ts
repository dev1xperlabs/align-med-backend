// base.service.ts
import { Injectable } from '@nestjs/common';
import { BaseRepository } from './base.repository';
import { BaseModel } from './base.model';
import { BaseListRequest, BaseListModel } from './base-list.dto';

@Injectable()
export class BaseService<T = any> {
  constructor(
    protected readonly repository: BaseRepository<T>,
    protected readonly model: BaseModel,
  ) { }

  // === Basic CRUD ===
  async create(data: Partial<T>): Promise<T> {
    return this.repository.create(data);
  }

  async findById(id: string | number): Promise<T | null> {
    return this.repository.findById(id);
  }

  async update(id: string | number, data: Partial<T>): Promise<T | null> {
    return this.repository.update(id, data);
  }

  async delete(id: string | number): Promise<T | null> {
    return this.repository.delete(id);
  }

  // === Listing ===
  async list(request: BaseListRequest): Promise<BaseListModel<T>> {
    return this.repository.list(request);
  }

  // === Custom Query Example ===
  async executeQuery<R = any>(sql: string, params: any[] = []): Promise<R[]> {
    const result = await this.repository.query<R>(sql, params);
    return result.rows;
  }
}
