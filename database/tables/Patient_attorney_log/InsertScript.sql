INSERT INTO public.patient_attorny_log(
	id, patient_id, attorney_id, visit_date, created_at, updated_at, location_id)
	VALUES (?, ?, ?, ?, ?, ?, ?);