-- FUNCTION: public.get_sum_of_billed_charges_by_attorney(bigint[], integer, integer, date, date)

-- DROP FUNCTION IF EXISTS public.get_sum_of_billed_charges_by_attorney(bigint[], integer, integer, date, date);

CREATE OR REPLACE FUNCTION public.get_sum_of_billed_charges_by_attorney(
	p_attorney_ids bigint[] DEFAULT NULL::bigint[],
	p_page_size integer DEFAULT 10,
	p_page_number integer DEFAULT 1,
	p_start_date date DEFAULT NULL::date,
	p_end_date date DEFAULT NULL::date)
    RETURNS TABLE(attorney_id bigint, billed_date date, attorney_name character varying, total_billed_charges numeric) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
BEGIN
    RETURN QUERY
    SELECT 
        b.attorney_id::BIGINT,  -- ✅ explicitly cast to BIGINT
        b.billed_date::DATE,
        COALESCE(a.name, 'Unknown Attorney') AS attorney_name,
        SUM(b.total_billed_charges)::NUMERIC AS total_billed_charges
    FROM public.bills b
    LEFT JOIN public.attornies a ON b.attorney_id = a.id
    WHERE (p_start_date IS NULL OR b.billed_date >= p_start_date)
      AND (p_end_date IS NULL OR b.billed_date <= p_end_date)
      AND (p_attorney_ids IS NULL OR b.attorney_id = ANY(p_attorney_ids))
      AND b.attorney_id IS NOT NULL
    GROUP BY b.attorney_id, b.billed_date, a.name
    HAVING SUM(b.total_billed_charges) > 0
    ORDER BY b.billed_date DESC, total_billed_charges DESC, b.attorney_id
    LIMIT p_page_size
    OFFSET (p_page_number - 1) * p_page_size;
END;
$BODY$;

ALTER FUNCTION public.get_sum_of_billed_charges_by_attorney(bigint[], integer, integer, date, date)
    OWNER TO postgres;
