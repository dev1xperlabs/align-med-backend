INSERT INTO public.patient_location_log(
	id, patient_id, location_id, visit_date, created_at, updated_at)
	VALUES (?, ?, ?, ?, ?, ?);