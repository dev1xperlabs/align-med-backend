export interface User {
  id: number;
  first_name: string;
  last_name: string;
  email: string;
  password: string;
  role_id?: number;
  created_at: Date;
  updated_at: Date;
  phone_number?: string;
  status?: string;
}

export interface ResponseUserDto {
  id: number;
  first_name: string;
  last_name: string;
  email: string;
  role_id?: number;
  created_at: Date;
  updated_at: Date;
}
