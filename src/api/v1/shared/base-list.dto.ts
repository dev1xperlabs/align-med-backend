// base-list-response.dto.ts
export class BaseListModel<T> {
  result: T[]; // The actual records
  totalRecords: number; // Total records matching criteria
  filteredRecords: number; // Total after filters (if different)
  startIndex?: number; // Echo back the request
  pageSize: number; // Echo back the request
  sortColumn?: string; // Echo back the request
  sortOrder?: 'ASC' | 'DESC'; // Echo back the request
  searchKeyword?: string; // Echo back the request
  // statusCode: string;
  // resultMessage: string;
  // error: string;
  // errorMessage: string
}

// base-list-request.dto.ts
export class BaseListRequest {
  searchKeyword?: string;
  startIndex?: number; // Now explicitly optional
  pageSize?: number;
  sortColumn?: string;
  sortOrder?: 'ASC' | 'DESC';

  get offset(): number {
    return this.startIndex || 0; // Provide default if needed
  }
}
