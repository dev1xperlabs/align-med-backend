INSERT INTO public.bills(
	id, patient_id, attorney_id, location_id, description, visit_date, billed_date, total_billed_charges, status, created_at, updated_at)
	VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);