-- FUNCTION: public.get_count_of_new_patients_by_location(integer, integer, date, date)

-- DROP FUNCTION IF EXISTS public.get_count_of_new_patients_by_location(integer, integer, date, date);

CREATE OR REPLACE FUNCTION public.get_count_of_new_patients_by_location(
	p_page_size integer DEFAULT 10,
	p_page_number integer DEFAULT 1,
	p_start_date date DEFAULT NULL::date,
	p_end_date date DEFAULT NULL::date)
    RETURNS TABLE(visit_date text, location_id bigint, location_name character varying, patient_count bigint, total_records bigint, current_page integer) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
BEGIN
    RETURN QUERY
    WITH filtered_data AS (
        SELECT 
            l.first_visit_date,
            l.location_id,
            ls.name AS location_name
        FROM public.patient_location_log l
        LEFT JOIN public.locations ls ON l.location_id = ls.id
        WHERE (p_start_date IS NULL OR l.first_visit_date >= p_start_date)
          AND (p_end_date IS NULL OR l.first_visit_date <= p_end_date)
    ),
    -- Step 1: Get distinct first_visit_dates, ordered descending, then paginate them
    paginated_dates AS (
        SELECT DISTINCT first_visit_date
        FROM filtered_data
        ORDER BY first_visit_date DESC
        LIMIT p_page_size
        OFFSET (p_page_number - 1) * p_page_size
    ),
    -- Step 2: Join back to get all data for selected dates
    grouped_data AS (
        SELECT 
            fd.first_visit_date,
            fd.location_id,
            fd.location_name,
            COUNT(*)::bigint AS patient_count
        FROM filtered_data fd
        JOIN paginated_dates pd ON fd.first_visit_date = pd.first_visit_date
        GROUP BY fd.first_visit_date, fd.location_id, fd.location_name
    ),
    -- Step 3: Get total distinct dates count for pagination
    total_count AS (
        SELECT COUNT(DISTINCT first_visit_date)::bigint AS total FROM filtered_data
    )
    SELECT 
        TO_CHAR(gd.first_visit_date + INTERVAL '3 days', 'FMMM/FMDD/YYYY') AS visit_date,
        gd.location_id,
        gd.location_name,
        gd.patient_count,
        tc.total,
        p_page_number
    FROM grouped_data gd
    CROSS JOIN total_count tc
    ORDER BY gd.first_visit_date DESC, gd.location_id;
END;
$BODY$;

ALTER FUNCTION public.get_count_of_new_patients_by_location(integer, integer, date, date)
    OWNER TO postgres;
