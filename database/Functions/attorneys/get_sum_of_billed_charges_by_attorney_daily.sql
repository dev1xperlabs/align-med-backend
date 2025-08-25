-- FUNCTION: public.get_sum_of_billed_charges_by_attorney_daily(date, date, integer, integer, bigint[])

-- DROP FUNCTION IF EXISTS public.get_sum_of_billed_charges_by_attorney_daily(date, date, integer, integer, bigint[]);

CREATE OR REPLACE FUNCTION public.get_sum_of_billed_charges_by_attorney_daily(
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
        JOIN bills b ON b.attorney_id = a.id
        WHERE b.billed_date BETWEEN start_date AND end_date
          AND (attorney_ids IS NULL OR a.id = ANY(attorney_ids))
    ) sub;

    -- Generate dates in the range
    WITH dates AS (
        SELECT generate_series(start_date, end_date, interval '1 day')::DATE AS billed_date
    ),
    filtered_attorneys AS (
        SELECT DISTINCT a.id, a.name AS attorney_name
        FROM attornies a
        JOIN bills b ON b.attorney_id = a.id
        WHERE b.billed_date BETWEEN start_date AND end_date
          AND (attorney_ids IS NULL OR a.id = ANY(attorney_ids))
    ),
    paginated_attorneys AS (
        SELECT *
        FROM filtered_attorneys
        ORDER BY attorney_name
        OFFSET (page_number - 1) * page_size
        LIMIT page_size
    ),
    daily_sums AS (
        SELECT 
            a.attorney_name,
            d.billed_date,
            TO_CHAR(COALESCE(SUM(b.total_billed_charges), 0), '"$"FM999999990.00') AS total_billed
        FROM paginated_attorneys a
        CROSS JOIN dates d
        LEFT JOIN bills b
            ON b.attorney_id = a.id
           AND b.billed_date = d.billed_date
        GROUP BY a.attorney_name, d.billed_date
    ),
    attorney_json AS (
        SELECT
            attorney_name,
            jsonb_object_agg(
                TO_CHAR(billed_date, 'FMMM/FMDD/YYYY'),  -- Format date as M/D/YYYY
                total_billed
                ORDER BY billed_date
            ) AS daily_json
        FROM daily_sums
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

ALTER FUNCTION public.get_sum_of_billed_charges_by_attorney_daily(date, date, integer, integer, bigint[])
    OWNER TO postgres;
