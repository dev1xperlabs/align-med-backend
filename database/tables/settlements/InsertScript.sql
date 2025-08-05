INSERT INTO public.settlements(
	id, patient_id, attorney_id, settlement_date, total_billed_charges, status, created_at, updated_at, settlement_percentage, settlement_amount)
	VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);