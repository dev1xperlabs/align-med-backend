-- FUNCTION: public.get_count_of_new_patients_by_location_daily(date, date, integer, integer)

-- DROP FUNCTION IF EXISTS public.get_count_of_new_patients_by_location_daily(date, date, integer, integer);

CREATE OR REPLACE FUNCTION public.get_count_of_new_patients_by_location_daily(
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
    total_days INT;
BEGIN
    -- Calculate total days between the dates
    SELECT COUNT(*) INTO total_days
    FROM generate_series(start_date, end_date, interval '1 day');

    -- Get all active locations
    WITH all_locations AS (
        SELECT id AS location_id, name AS location_name
        FROM locations
        WHERE status = B'1'
    ),

    -- Get all dates in the range
    full_dates AS (
        SELECT generate_series(start_date, end_date, interval '1 day')::DATE AS visit_date
    ),

    -- Paginate days
    paginated_days AS (
        SELECT visit_date
        FROM full_dates
        ORDER BY visit_date DESC
        OFFSET (page_number - 1) * page_size
        LIMIT page_size
    ),

    -- Combine days and locations
    day_location_combinations AS (
        SELECT d.visit_date, l.location_id, l.location_name
        FROM paginated_days d
        CROSS JOIN all_locations l
    ),

    -- Count distinct new patients for each (day, location)
    daily_counts AS (
        SELECT 
            dlc.visit_date,
            dlc.location_name,
            COUNT(DISTINCT pll.patient_id) AS patient_count
        FROM day_location_combinations dlc
        LEFT JOIN patient_location_log pll
            ON pll.location_id = dlc.location_id
            AND pll.first_visit_date = dlc.visit_date
        GROUP BY dlc.visit_date, dlc.location_name
    ),

    -- Build JSON structure
    day_json_data AS (
        SELECT 
            TO_CHAR(visit_date, 'MM/DD/YYYY') AS date,
            jsonb_object_agg(location_name, 
                CASE 
                    WHEN patient_count = 0 THEN '-' 
                    ELSE patient_count::TEXT 
                END
                ORDER BY location_name
            ) AS locations_json
        FROM daily_counts
        GROUP BY visit_date
        ORDER BY visit_date DESC
    )

    -- Final aggregation
    SELECT jsonb_build_object(
        'data', 
        jsonb_agg(jsonb_build_object('date', date) || locations_json),
        'totalRecords', total_days,
        'currentPage', page_number
    )
    INTO result
    FROM day_json_data;

    RETURN result;
END;
$BODY$;

ALTER FUNCTION public.get_count_of_new_patients_by_location_daily(date, date, integer, integer)
    OWNER TO postgres;
