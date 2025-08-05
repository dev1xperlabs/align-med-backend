-- FUNCTION: public.get_billing_summary()

-- DROP FUNCTION IF EXISTS public.get_billing_summary();

CREATE OR REPLACE FUNCTION public.get_billing_summary(
	)
    RETURNS TABLE(total_billed_today numeric, total_billed_this_week numeric, total_billed_this_month numeric, total_billed_this_year numeric) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
BEGIN
  RETURN QUERY
  SELECT
    COALESCE(SUM(total_billed_charges) FILTER (WHERE billed_date::DATE = CURRENT_DATE), 0)::NUMERIC AS total_billed_today,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE billed_date >= date_trunc('week', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_week,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE billed_date >= date_trunc('month', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_month,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE billed_date >= date_trunc('year', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_year
  FROM public.bills
  WHERE billed_date IS NOT NULL;
END;
$BODY$;

ALTER FUNCTION public.get_billing_summary()
    OWNER TO postgres;
