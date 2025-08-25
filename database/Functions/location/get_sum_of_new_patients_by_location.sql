-- FUNCTION: public.get_sum_of_new_patients_by_location(integer, integer, date, date)

-- DROP FUNCTION IF EXISTS public.get_sum_of_new_patients_by_location(integer, integer, date, date);

CREATE OR REPLACE FUNCTION public.get_sum_of_new_patients_by_location(
	p_page_size integer DEFAULT 10,
	p_page_number integer DEFAULT 1,
	p_start_date date DEFAULT NULL::date,
	p_end_date date DEFAULT NULL::date)
    RETURNS TABLE(visit_date text, location_id bigint, location_name character varying, total_revenue numeric, total_patient_visits bigint, total_records bigint, current_page integer) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
BEGIN
    RETURN QUERY
    WITH filtered_data AS (
        SELECT 
            COALESCE(b.location_id, pl.location_id) AS location_id,
            pl.visit_date,
            b.patient_id,
            b.total_billed_charges
        FROM public.bills b
        LEFT JOIN public.patient_location_log pl 
            ON b.patient_id = pl.patient_id
        WHERE (p_start_date IS NULL OR pl.visit_date >= p_start_date)
          AND (p_end_date IS NULL OR pl.visit_date <= p_end_date)
    ),
    aggregated AS (
        SELECT
            f.visit_date,
            f.location_id,
            COALESCE(l.name, 'Unknown Location') AS location_name,
            SUM(f.total_billed_charges)::NUMERIC AS total_revenue,
            COUNT(DISTINCT f.patient_id)::BIGINT AS total_patient_visits
        FROM filtered_data f
        LEFT JOIN public.locations l ON f.location_id = l.id
        GROUP BY f.visit_date, f.location_id, l.name
        HAVING SUM(f.total_billed_charges) > 0
    ),
    total_count AS (
        SELECT COUNT(*)::bigint AS total FROM aggregated
    )
    SELECT 
        TO_CHAR(a.visit_date, 'FMMM/FMDD/YYYY') AS visit_date,
        a.location_id,
        a.location_name,
        a.total_revenue,
        a.total_patient_visits,
        tc.total AS total_records,
        p_page_number AS current_page
    FROM aggregated a
    CROSS JOIN total_count tc
    ORDER BY a.visit_date DESC, a.location_id
    LIMIT p_page_size
    OFFSET (p_page_number - 1) * p_page_size;
END;
$BODY$;

ALTER FUNCTION public.get_sum_of_new_patients_by_location(integer, integer, date, date)
    OWNER TO postgres;
