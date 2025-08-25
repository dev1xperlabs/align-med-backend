-- FUNCTION: public.get_count_of_patients_by_attorney(bigint[], integer, integer, date, date)

-- DROP FUNCTION IF EXISTS public.get_count_of_patients_by_attorney(bigint[], integer, integer, date, date);

CREATE OR REPLACE FUNCTION public.get_count_of_patients_by_attorney(
	p_attorney_ids bigint[] DEFAULT NULL::bigint[],
	p_page_size integer DEFAULT 10,
	p_page_number integer DEFAULT 1,
	p_start_date date DEFAULT NULL::date,
	p_end_date date DEFAULT NULL::date)
    RETURNS TABLE(visit_date date, attorney_id bigint, attorney_name character varying, patient_count bigint) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
BEGIN
    RETURN QUERY
    SELECT 
        pal.visit_date::DATE,  
        pal.attorney_id,
        a.name AS attorney_name,  
        COUNT(pal.patient_id)::BIGINT as patient_count
    FROM public.patient_attorny_log pal
    LEFT JOIN public.attornies a ON pal.attorney_id = a.id  
    WHERE (p_start_date IS NULL OR pal.visit_date >= p_start_date)
        AND (p_end_date IS NULL OR pal.visit_date <= p_end_date)
        AND (p_attorney_ids IS NULL OR pal.attorney_id = ANY(p_attorney_ids))
    GROUP BY pal.visit_date, pal.attorney_id, a.name
    ORDER BY pal.visit_date DESC, pal.attorney_id
    LIMIT p_page_size
    OFFSET (p_page_number - 1) * p_page_size;
END;
$BODY$;

ALTER FUNCTION public.get_count_of_patients_by_attorney(bigint[], integer, integer, date, date)
    OWNER TO postgres;
