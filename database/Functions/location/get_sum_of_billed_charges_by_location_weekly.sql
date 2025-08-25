-- FUNCTION: public.get_sum_of_billed_charges_by_location_weekly(date, date, integer, integer)

-- DROP FUNCTION IF EXISTS public.get_sum_of_billed_charges_by_location_weekly(date, date, integer, integer);

CREATE OR REPLACE FUNCTION public.get_sum_of_billed_charges_by_location_weekly(
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
    total_weeks INT;
BEGIN
    -- Step 1: Get total weeks in the range
    SELECT COUNT(*) INTO total_weeks
    FROM (
        SELECT DISTINCT EXTRACT(WEEK FROM billed_date)::INT AS week_number
        FROM bills
        WHERE billed_date BETWEEN start_date AND end_date
    ) AS week_cte;

    -- Step 2: Build CTEs
    WITH weeks_in_range AS (
        SELECT DISTINCT EXTRACT(WEEK FROM billed_date)::INT AS week_number
        FROM bills
        WHERE billed_date BETWEEN start_date AND end_date
    ),
    
    paginated_weeks AS (
        SELECT week_number
        FROM weeks_in_range
        ORDER BY week_number DESC
        OFFSET (page_number - 1) * page_size
        LIMIT page_size
    ),

    all_locations AS (
        SELECT id AS location_id, name AS location_name
        FROM locations
        WHERE status = B'1'
    ),

    week_location_combinations AS (
        SELECT w.week_number, l.location_id, l.location_name
        FROM paginated_weeks w
        CROSS JOIN all_locations l
    ),

    weekly_bills AS (
        SELECT 
            wlc.week_number,
            wlc.location_name,
            COALESCE(SUM(b.total_billed_charges), 0) AS total_charges
        FROM week_location_combinations wlc
        LEFT JOIN bills b
            ON b.location_id = wlc.location_id
            AND EXTRACT(WEEK FROM b.billed_date)::INT = wlc.week_number
            AND b.billed_date BETWEEN start_date AND end_date
        GROUP BY wlc.week_number, wlc.location_name
    ),

    week_json_data AS (
        SELECT 
            'Week ' || week_number AS date,
            jsonb_object_agg(location_name, TO_CHAR(total_charges, '"$"FM999999990.00') ORDER BY location_name) AS locations_json
        FROM weekly_bills
        GROUP BY week_number
        ORDER BY week_number DESC
    )

    -- Step 3: Final result
    SELECT jsonb_build_object(
        'data', jsonb_agg(jsonb_build_object('date', date) || locations_json),
        'totalRecords', total_weeks,
        'currentPage', page_number
    )
    INTO result
    FROM week_json_data;

    RETURN result;
END;
$BODY$;

ALTER FUNCTION public.get_sum_of_billed_charges_by_location_weekly(date, date, integer, integer)
    OWNER TO postgres;
