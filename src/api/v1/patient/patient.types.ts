export interface Patient {
  id: number;
  first_name: string;
  last_name: string;
  email: string;
  phone: string;
  date_of_birth: Date;
  gender: string;
  blood_type?: string;
  address?: string;
  status: boolean;
  created_at: Date;
  updated_at: Date;
}

// export interface CreatePatientDto {
//   first_name: string;
//   last_name: string;
//   email: string;
//   phone: string;
//   date_of_birth: Date;
//   gender: string;
//   blood_type?: string;
//   address?: string;
// }

export interface CreatePatientDto {
  external_mrn: string;
  first_name: string;
  middle_name?: string;
  last_name: string;
  dob: Date;
  email: string;
  phone_number: string;
  gender: string;
  status?: "0" | "1";
}



export interface UpdatePatientDto extends Partial<CreatePatientDto> {
  status?: "0" | "1";
}

