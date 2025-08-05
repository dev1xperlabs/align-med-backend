// base.model.ts
export class BaseModel {
  // Required
  tableName: string;

  // Search configuration
  searchableColumns: string[] = []; // Columns for WHERE ILIKE '%keyword%'

  // Defaults
  defaultPageSize: number = 10;
  maxPageSize: number = 100;
  defaultSortColumn: string = 'id';
  defaultSortOrder: 'ASC' | 'DESC' = 'ASC';

  // Column whitelists
  sortableColumns: string[] = ['id']; // Columns allowed for sorting
  filterableColumns: string[] = []; // Columns for exact-match WHERE

  constructor(config: Partial<BaseModel> = {}) {
    Object.assign(this, config);
  }

  // Validate/sanitize sort column
  validateSortColumn(column: string): string {
    return this.sortableColumns.includes(column)
      ? column
      : this.defaultSortColumn;
  }
}
