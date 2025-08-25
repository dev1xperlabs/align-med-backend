-- FUNCTION: public.get_sum_of_billed_charges_by_attorney_weekly(date, date, integer, integer, bigint[])

-- DROP FUNCTION IF EXISTS public.get_sum_of_billed_charges_by_attorney_weekly(date, date, integer, integer, bigint[]);

CREATE OR REPLACE FUNCTION public.get_sum_of_billed_charges_by_attorney_weekly(
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
    -- Count total unique attorneys for pagination
    SELECT COUNT(DISTINCT attorney_id)
    INTO total_records
    FROM bills
    WHERE billed_date BETWEEN start_date AND end_date
      AND (attorney_ids IS NULL OR attorney_id = ANY(attorney_ids));

    -- Build paginated list and weekly data up to max_week only
    WITH filtered_attorneys AS (
        SELECT DISTINCT a.id AS attorney_id, a.name AS attorney_name
        FROM bills b
        JOIN attornies a ON a.id = b.attorney_id
        WHERE b.billed_date BETWEEN start_date AND end_date
          AND (attorney_ids IS NULL OR b.attorney_id = ANY(attorney_ids))
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
            COALESCE(b.total_charges, 0) AS billed_charges
        FROM paginated_attorneys pa
        CROSS JOIN generate_series(1, max_week) AS w(week_number)
        LEFT JOIN LATERAL (
            SELECT SUM(total_billed_charges) AS total_charges
            FROM bills b
            WHERE b.attorney_id = pa.attorney_id
              AND EXTRACT(WEEK FROM b.billed_date)::INT = w.week_number
              AND b.billed_date BETWEEN start_date AND end_date
        ) b ON TRUE
    ),
    attorney_json AS (
        SELECT 
            attorney_name,
            jsonb_object_agg(
                'Week ' || week_number::TEXT, 
                '$' || ROUND(billed_charges::NUMERIC, 2)::TEXT
                ORDER BY week_number ASC
            ) AS weeks_json
        FROM weekly_data
        GROUP BY attorney_name
    )

    -- Build final JSON
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

ALTER FUNCTION public.get_sum_of_billed_charges_by_attorney_weekly(date, date, integer, integer, bigint[])
    OWNER TO postgres;
