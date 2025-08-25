-- FUNCTION: public.get_sum_of_billed_charges_by_location_daily(date, date, integer, integer)

-- DROP FUNCTION IF EXISTS public.get_sum_of_billed_charges_by_location_daily(date, date, integer, integer);

CREATE OR REPLACE FUNCTION public.get_sum_of_billed_charges_by_location_daily(
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
    -- Count total days in range
    SELECT COUNT(*) INTO total_days
    FROM generate_series(start_date, end_date, INTERVAL '1 day');

    -- All active locations
    WITH all_locations AS (
        SELECT id AS location_id, name AS location_name
        FROM locations
        WHERE status = B'1'
    ),

    -- Generate daily date series
    all_days AS (
        SELECT generate_series(start_date, end_date, interval '1 day')::DATE AS visit_date
    ),

    -- Paginate the date range
    paginated_days AS (
        SELECT visit_date
        FROM all_days
        ORDER BY visit_date DESC
        OFFSET (page_number - 1) * page_size
        LIMIT page_size
    ),

    -- Combine each date with each location
    date_location_combinations AS (
        SELECT d.visit_date, l.location_id, l.location_name
        FROM paginated_days d
        CROSS JOIN all_locations l
    ),

    -- Sum billed charges per (date, location)
    daily_bills AS (
        SELECT 
            dlc.visit_date,
            dlc.location_name,
            COALESCE(SUM(b.total_billed_charges), 0) AS total_charges
        FROM date_location_combinations dlc
        LEFT JOIN bills b
            ON b.location_id = dlc.location_id
            AND b.billed_date::DATE = dlc.visit_date
        GROUP BY dlc.visit_date, dlc.location_name
    ),

    -- Format final JSON structure
    formatted_data AS (
        SELECT 
            TO_CHAR(visit_date, 'MM/DD/YYYY') AS date,
            jsonb_object_agg(location_name, TO_CHAR(total_charges, '"$"FM999999990.00') ORDER BY location_name) AS locations_json
        FROM daily_bills
        GROUP BY visit_date
        ORDER BY visit_date DESC
    )

    -- Final response
    SELECT jsonb_build_object(
        'data', 
        jsonb_agg(jsonb_build_object('date', date) || locations_json),
        'totalRecords', total_days,
        'currentPage', page_number
    )
    INTO result
    FROM formatted_data;

    RETURN result;
END;
$BODY$;

ALTER FUNCTION public.get_sum_of_billed_charges_by_location_daily(date, date, integer, integer)
    OWNER TO postgres;
