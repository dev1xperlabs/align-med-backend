-- FUNCTION: public.get_settlements_billing()

-- DROP FUNCTION IF EXISTS public.get_settlements_billing();

CREATE OR REPLACE FUNCTION public.get_settlements_billing(
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
    COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date::DATE = CURRENT_DATE), 0)::NUMERIC AS total_billed_today,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date >= date_trunc('week', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_week,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date >= date_trunc('month', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_month,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date >= date_trunc('year', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_year
  FROM public.settlements
  WHERE settlement_date IS NOT NULL;
END;
$BODY$;

ALTER FUNCTION public.get_settlements_billing()
    OWNER TO postgres;
