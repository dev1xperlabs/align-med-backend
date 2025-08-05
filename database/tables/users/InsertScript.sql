INSERT INTO public.users(
	id, first_name, last_name, email, password_hash, created_at, updated_at, phone_number, status)
	VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);