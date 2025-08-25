-- FUNCTION: public.get_count_of_new_patients_by_attorney_daily(date, date, integer, integer, bigint[])

-- DROP FUNCTION IF EXISTS public.get_count_of_new_patients_by_attorney_daily(date, date, integer, integer, bigint[]);

CREATE OR REPLACE FUNCTION public.get_count_of_new_patients_by_attorney_daily(
	start_date date,
	end_date date,
	page_size integer,
	page_number integer,
	attorney_ids bigint[] DEFAULT NULL::bigint[])
    RETURNS jsonb
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    result JSONB;
    total_records INT;
BEGIN
    -- Count total attorneys in date range (with optional filtering)
    SELECT COUNT(*) INTO total_records
    FROM (
        SELECT DISTINCT a.id
        FROM attornies a
        JOIN patient_attorny_log apl ON apl.attorney_id = a.id
        WHERE apl.first_visit_date BETWEEN start_date AND end_date
          AND (attorney_ids IS NULL OR a.id = ANY(attorney_ids))
    ) sub;

    -- Generate dates in the range
    WITH dates AS (
        SELECT generate_series(start_date, end_date, interval '1 day')::DATE AS visit_date
    ),
    filtered_attorneys AS (
        SELECT DISTINCT a.id, a.name AS attorney_name
        FROM attornies a
        JOIN patient_attorny_log apl ON apl.attorney_id = a.id
        WHERE apl.first_visit_date BETWEEN start_date AND end_date
          AND (attorney_ids IS NULL OR a.id = ANY(attorney_ids))
    ),
    paginated_attorneys AS (
        SELECT *
        FROM filtered_attorneys
        ORDER BY attorney_name
        OFFSET (page_number - 1) * page_size
        LIMIT page_size
    ),
    daily_counts AS (
        SELECT 
            a.attorney_name,
            d.visit_date,
            COUNT(DISTINCT apl.patient_id) AS patient_count
        FROM paginated_attorneys a
        CROSS JOIN dates d
        LEFT JOIN patient_attorny_log apl
            ON apl.attorney_id = a.id
            AND apl.first_visit_date = d.visit_date
        GROUP BY a.attorney_name, d.visit_date
    ),
    attorney_json AS (
        SELECT
            attorney_name,
            jsonb_object_agg(
                TO_CHAR(visit_date, 'FMMM/FMDD/YYYY'),  -- Format date as M/D/YYYY
                patient_count
                ORDER BY visit_date
            ) AS daily_json
        FROM daily_counts
        GROUP BY attorney_name
    )
    SELECT jsonb_build_object(
        'data', jsonb_agg(
            jsonb_build_object('attorney', attorney_name) || daily_json
        ),
        'totalRecords', total_records,
        'currentPage', page_number
    )
    INTO result
    FROM attorney_json;

    RETURN result;
END;
$BODY$;

ALTER FUNCTION public.get_count_of_new_patients_by_attorney_daily(date, date, integer, integer, bigint[])
    OWNER TO postgres;
