-- FUNCTION: public.get_new_patient_summary()

-- DROP FUNCTION IF EXISTS public.get_new_patient_summary();

CREATE OR REPLACE FUNCTION public.get_new_patient_summary(
	)
    RETURNS TABLE(new_patients_today integer, new_patients_this_week integer, new_patients_this_month integer, new_patients_this_year integer) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
BEGIN
  RETURN QUERY
  SELECT
    COUNT(*) FILTER (WHERE first_visit_date::DATE = CURRENT_DATE)::INTEGER AS new_patients_today,
    COUNT(*) FILTER (WHERE first_visit_date >= date_trunc('week', CURRENT_DATE))::INTEGER AS new_patients_this_week,
    COUNT(*) FILTER (WHERE first_visit_date >= date_trunc('month', CURRENT_DATE))::INTEGER AS new_patients_this_month,
    COUNT(*) FILTER (WHERE first_visit_date >= date_trunc('year', CURRENT_DATE))::INTEGER AS new_patients_this_year
  FROM public.patients
  WHERE created_at IS NOT NULL;
END;
$BODY$;

ALTER FUNCTION public.get_new_patient_summary()
    OWNER TO postgres;
