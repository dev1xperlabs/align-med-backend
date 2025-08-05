INSERT INTO public.patients(
	id, external_mrn, first_name, middle_name, last_name, dob, email, phone_number, status, created_at, updated_at, gender)
	VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);