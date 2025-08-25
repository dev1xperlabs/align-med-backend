CREATE OR REPLACE FUNCTION public.get_sum_of_billed_charges_by_location_weekly_test(
    start_date date,
    end_date date,
    page_size integer,
    page_number integer
)
RETURNS jsonb
LANGUAGE plpgsql
AS $BODY$
DECLARE
    result JSONB;
BEGIN
    -- Step 1: Generate all weeks in the given range
    WITH weeks_in_range AS (
        SELECT generate_series(
            date_trunc('week', start_date),
            date_trunc('week', end_date),
            interval '1 week'
        )::date AS week_start
    ),
    
    -- count total weeks for pagination meta
    total_weeks_cte AS (
        SELECT COUNT(*) AS total_weeks_count FROM weeks_in_range
    ),
    
    paginated_weeks AS (
        SELECT week_start
        FROM weeks_in_range
        ORDER BY week_start DESC
        OFFSET (page_number - 1) * page_size
        LIMIT page_size
    ),

    all_locations AS (
        SELECT id AS location_id, name AS location_name
        FROM locations
        WHERE status = B'1'
    ),

    week_location_combinations AS (
        SELECT w.week_start, l.location_id, l.location_name
        FROM paginated_weeks w
        CROSS JOIN all_locations l
    ),

    weekly_bills AS (
        SELECT 
            wlc.week_start,
            wlc.location_name,
            COALESCE(SUM(b.total_billed_charges), 0) AS total_charges
        FROM week_location_combinations wlc
        LEFT JOIN bills b
            ON b.location_id = wlc.location_id
            AND date_trunc('week', b.billed_date) = wlc.week_start
            AND b.billed_date BETWEEN start_date AND end_date
        GROUP BY wlc.week_start, wlc.location_name
    ),

    week_json_data AS (
        SELECT 
            TO_CHAR(week_start, '"Week of "YYYY-MM-DD') AS date,
            jsonb_object_agg(location_name, TO_CHAR(total_charges, '"$"FM999999990.00') ORDER BY location_name) AS locations_json
        FROM weekly_bills
        GROUP BY week_start
        ORDER BY week_start DESC
    )

    -- Step 2: Final result
    SELECT jsonb_build_object(
        'data', jsonb_agg(jsonb_build_object('date', date) || locations_json),
        'totalRecords', (SELECT total_weeks_count FROM total_weeks_cte),
        'currentPage', page_number
    )
    INTO result
    FROM week_json_data;

    RETURN result;
END;
$BODY$;

ALTER FUNCTION public.get_sum_of_billed_charges_by_location_weekly_test(date, date, integer, integer)
    OWNER TO postgres;



SELECT public.get_sum_of_billed_charges_by_location_weekly_test(
    '2025-01-01', 
    '2025-08-25', 
    10, 
    1
);
