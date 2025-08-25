-- FUNCTION: public.get_count_of_new_patients_by_location_weekly(date, date, integer, integer)

-- DROP FUNCTION IF EXISTS public.get_count_of_new_patients_by_location_weekly(date, date, integer, integer);

CREATE OR REPLACE FUNCTION public.get_count_of_new_patients_by_location_weekly(
	start_date date,
	end_date date,
	page_size integer,
	page_number integer)
    RETURNS jsonb
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
    result JSONB;
    max_week INT := EXTRACT(WEEK FROM end_date)::INT;
    total_weeks INT := max_week;
BEGIN
    -- Get all active locations
    WITH all_locations AS (
        SELECT id AS location_id, name AS location_name
        FROM locations
        WHERE status = B'1'
    ),

    -- Get all week numbers up to max_week
    full_weeks AS (
        SELECT generate_series(1, max_week) AS week_number
    ),

    -- Paginate weeks in descending order
    paginated_weeks AS (
        SELECT week_number
        FROM full_weeks
        ORDER BY week_number DESC
        OFFSET (page_number - 1) * page_size
        LIMIT page_size
    ),

    -- Combine weeks and locations
    week_location_combinations AS (
        SELECT w.week_number, l.location_id, l.location_name
        FROM paginated_weeks w
        CROSS JOIN all_locations l
    ),

    -- Count distinct new patients for each (week, location)
    weekly_counts AS (
        SELECT 
            wlc.week_number,
            wlc.location_name,
            COUNT(DISTINCT pll.patient_id) AS patient_count
        FROM week_location_combinations wlc
        LEFT JOIN patient_location_log pll
            ON pll.location_id = wlc.location_id
            AND EXTRACT(WEEK FROM pll.first_visit_date)::INT = wlc.week_number
            AND pll.first_visit_date BETWEEN start_date AND end_date
        GROUP BY wlc.week_number, wlc.location_name
    ),

    -- Build JSON structure
    week_json_data AS (
        SELECT 
            'Week ' || week_number AS date,
            jsonb_object_agg(
                location_name, 
                CASE 
                    WHEN patient_count = 0 THEN '-' 
                    ELSE patient_count::TEXT 
                END
                ORDER BY location_name
            ) AS locations_json
        FROM weekly_counts
        GROUP BY week_number
        ORDER BY week_number DESC
    )

    -- Final aggregation
    SELECT jsonb_build_object(
        'data', 
        jsonb_agg(jsonb_build_object('date', date) || locations_json),
        'totalRecords', total_weeks,
        'currentPage', page_number
    )
    INTO result
    FROM week_json_data;

    RETURN result;
END;
$BODY$;

ALTER FUNCTION public.get_count_of_new_patients_by_location_weekly(date, date, integer, integer)
    OWNER TO postgres;
