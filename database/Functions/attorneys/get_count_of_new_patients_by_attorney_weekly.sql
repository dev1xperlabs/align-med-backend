-- FUNCTION: public.get_count_of_new_patients_by_attorney_weekly(date, date, integer, integer, bigint[])

-- DROP FUNCTION IF EXISTS public.get_count_of_new_patients_by_attorney_weekly(date, date, integer, integer, bigint[]);

CREATE OR REPLACE FUNCTION public.get_count_of_new_patients_by_attorney_weekly(
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
    max_week INT := EXTRACT(WEEK FROM end_date)::INT;
BEGIN
    -- Get total number of distinct attorneys in the time range (with optional filtering)
    SELECT COUNT(DISTINCT attorney_id)
    INTO total_records
    FROM patient_attorny_log
    WHERE first_visit_date BETWEEN start_date AND end_date
      AND (
          attorney_ids IS NULL OR attorney_id = ANY(attorney_ids)
      );

    -- Get paginated attorney names + IDs ordered by name
    WITH filtered_attorneys AS (
        SELECT DISTINCT a.id AS attorney_id, a.name AS attorney_name
        FROM patient_attorny_log pal
        JOIN attornies a ON a.id = pal.attorney_id
        WHERE pal.first_visit_date BETWEEN start_date AND end_date
          AND (
              attorney_ids IS NULL OR pal.attorney_id = ANY(attorney_ids)
          )
    ),
    paginated_attorneys AS (
        SELECT *
        FROM filtered_attorneys
        ORDER BY attorney_name
        OFFSET (page_number - 1) * page_size
        LIMIT page_size
    ),
    weekly_data AS (
        SELECT 
            pa.attorney_name,
            w.week_number,
            COALESCE(p.patient_count, 0) AS patient_count
        FROM paginated_attorneys pa
        CROSS JOIN generate_series(1, max_week) AS w(week_number)
        LEFT JOIN LATERAL (
            SELECT COUNT(DISTINCT patient_id) AS patient_count
            FROM patient_attorny_log apl
            WHERE apl.attorney_id = pa.attorney_id
              AND EXTRACT(WEEK FROM apl.first_visit_date)::INT = w.week_number
              AND apl.first_visit_date BETWEEN start_date AND end_date
        ) p ON TRUE
    ),
    attorney_json AS (
        SELECT 
            attorney_name,
            jsonb_object_agg(
                'Week ' || week_number::TEXT,
                patient_count
                ORDER BY week_number DESC
            ) AS weeks_json
        FROM weekly_data
        GROUP BY attorney_name
    )

    -- Final JSON output
    SELECT jsonb_build_object(
        'data', jsonb_agg(
            jsonb_build_object('attorney', attorney_name) || weeks_json
        ),
        'totalRecords', total_records,
        'currentPage', page_number
    )
    INTO result
    FROM attorney_json;

    RETURN result;
END;
$BODY$;

ALTER FUNCTION public.get_count_of_new_patients_by_attorney_weekly(date, date, integer, integer, bigint[])
    OWNER TO postgres;
