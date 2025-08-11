// base.repository.ts
import { Inject, Injectable } from '@nestjs/common';
import { Pool, QueryResult, PoolClient } from 'pg';
import { BaseModel } from './base.model';
import { BaseListRequest, BaseListModel } from './base-list.dto';
import { DatabaseService } from '../../../database/database.service';

@Injectable()
export class BaseRepository<T = any> {
  protected model: BaseModel;

  constructor(
    protected readonly database_service: DatabaseService,
    modelConfig: Partial<BaseModel>,
  ) {
    this.model = new BaseModel(modelConfig);
  }

  // === CRUD Operations ===
  async create(data: Partial<T>, returning: string[] = ['*']): Promise<T> {
    const columns = Object.keys(data);
    const values = Object.values(data);
    const placeholders = columns.map((_, i) => `$${i + 1}`).join(', ');

    const query = `
      INSERT INTO ${this.model.tableName} (${columns.join(', ')})
      VALUES (${placeholders})
      RETURNING ${returning.join(', ')}
    `;

    const result = await this.database_service.query<T>(query, values);
    return result.rows[0];
  }

  async findById(
    id: string | number,
    columns: string[] = ['*'],
  ): Promise<T | null> {
    const result = await this.database_service.query<T>(
      `SELECT ${columns.join(', ')} FROM ${this.model.tableName} WHERE id = $1 LIMIT 1`,
      [id],
    );
    return result.rows[0] || null;
  }

  async findAll(options: {
    columns?: string[];
    orderBy?: string;
    orderDirection?: 'ASC' | 'DESC';
    limit?: number;
    offset?: number;
    where?: { [key: string]: any };
  } = {}): Promise<T[]> {
    const {
      columns = ['*'],
      orderBy = this.model.defaultSortColumn,
      orderDirection = this.model.defaultSortOrder,
      limit,
      offset,
      where = {},
    } = options;

    // Build WHERE clause
    const whereConditions: string[] = [];
    const params: any[] = [];

    Object.entries(where).forEach(([key, value]) => {
      if (value !== undefined && value !== null) {
        whereConditions.push(`${key} = $${params.length + 1}`);
        params.push(value);
      }
    });

    const whereClause = whereConditions.length > 0
      ? `WHERE ${whereConditions.join(' AND ')}`
      : '';

    // Build ORDER BY clause
    const validatedOrderBy = this.model.validateSortColumn(orderBy);
    const orderClause = `ORDER BY ${validatedOrderBy} ${orderDirection}`;

    // Build LIMIT and OFFSET
    let limitClause = '';
    if (limit !== undefined) {
      limitClause += ` LIMIT $${params.length + 1}`;
      params.push(limit);

      if (offset !== undefined) {
        limitClause += ` OFFSET $${params.length + 1}`;
        params.push(offset);
      }
    }

    const query = `
      SELECT ${columns.join(', ')}
      FROM ${this.model.tableName}
      ${whereClause}
      ${orderClause}
      ${limitClause}
    `;

    const result = await this.database_service.query<T>(query, params);
    return result.rows;
  }

  async update(
    id: string | number | undefined,
    data: Partial<T>,
    returning: string[] = ['*'],
  ): Promise<T | null> {
    const updates = Object.keys(data)
      .map((key, i) => `${key} = $${i + 1}`)
      .join(', ');
    const values = [...Object.values(data), id];

    const query = `
      UPDATE ${this.model.tableName}
      SET ${updates}
      WHERE id = $${values.length}
      RETURNING ${returning.join(', ')}
    `;

    const result = await this.database_service.query<T>(query, values);
    return result.rows[0] || null;
  }

  async delete(
    id: string | number,
    returning: string[] = ['id'],
  ): Promise<T | null> {
    const result = await this.database_service.query<T>(
      `DELETE FROM ${this.model.tableName} WHERE id = $1 RETURNING ${returning.join(', ')}`,
      [id],
    );
    return result.rows[0] || null;
  }
  // ====Custom Query Execution ====
  async callFunction<R = any>(
    functionName: string,
    params: any[] = [],
  ): Promise<R[]> {
    const paramPlaceholders = params.map((_, i) => `$${i + 1}`).join(', ');
    const sql = `SELECT * FROM ${functionName}(${paramPlaceholders})`;

    const result = await this.database_service.query<R>(sql, params);
    return result.rows;
  }


  // === Advanced Listing ===
  async list(request: BaseListRequest): Promise<BaseListModel<T>> {
    // Sanitize inputs
    const pageSize = Math.min(
      request.pageSize || this.model.defaultPageSize,
      this.model.maxPageSize,
    );

    // Handle undefined sortColumn case
    const sortColumn = request.sortColumn
      ? this.model.validateSortColumn(request.sortColumn)
      : this.model.defaultSortColumn;

    const sortOrder = request.sortOrder || this.model.defaultSortOrder;

    // Build WHERE clauses
    const whereClauses: string[] = [];
    const params: any[] = [];

    // Keyword search
    if (request.searchKeyword && this.model.searchableColumns.length > 0) {
      const searchConditions = this.model.searchableColumns
        .map((col) => `${col} ILIKE $${params.length + 1}`)
        .join(' OR ');
      params.push(`%${request.searchKeyword}%`);
      whereClauses.push(`(${searchConditions})`);
    }

    const whereClause = whereClauses.length
      ? `WHERE ${whereClauses.join(' AND ')}`
      : '';

    // Execute queries
    const [dataResult, countResult] = await Promise.all([
      this.database_service.query<T>(
        `
        SELECT * FROM ${this.model.tableName}
        ${whereClause}
        ORDER BY ${sortColumn} ${sortOrder}
        LIMIT $${params.length + 1} OFFSET $${params.length + 2}
      `,
        [...params, pageSize, request.offset],
      ),

      this.database_service.query<{ count: string }>(
        `
        SELECT COUNT(*) FROM ${this.model.tableName}
        ${whereClause}
      `,
        params,
      ),
    ]);

    return {
      result: dataResult.rows,
      totalRecords: parseInt(countResult.rows[0].count, 10),
      filteredRecords: parseInt(countResult.rows[0].count, 10),
      startIndex: request.startIndex,
      pageSize,
      sortColumn,
      sortOrder,
      searchKeyword: request.searchKeyword,
    };
  }

  async query<R = any>(
    sql: string,
    params: any[] = [],
  ): Promise<QueryResult<R>> {
    return this.database_service.query<R>(sql, params);
  }
}
