-- FUNCTION: public.get_settlement_by_attorneys_weekly(date, date, integer, integer, bigint[])

-- DROP FUNCTION IF EXISTS public.get_settlement_by_attorneys_weekly(date, date, integer, integer, bigint[]);

CREATE OR REPLACE FUNCTION public.get_settlement_by_attorneys_weekly(
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
    -- Count total distinct attorneys in time range (with optional filtering)
    SELECT COUNT(DISTINCT attorney_id)
    INTO total_records
    FROM settlements
    WHERE settlement_date BETWEEN start_date AND end_date
      AND (attorney_ids IS NULL OR attorney_id = ANY(attorney_ids));

    -- CTE: Paginated attorneys with settlements
    WITH filtered_attorneys AS (
        SELECT DISTINCT a.id AS attorney_id, a.name AS attorney_name
        FROM settlements s
        JOIN attornies a ON a.id = s.attorney_id
        WHERE s.settlement_date BETWEEN start_date AND end_date
          AND (attorney_ids IS NULL OR s.attorney_id = ANY(attorney_ids))
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
            COALESCE(s.total_amount, 0) AS settlement_amount
        FROM paginated_attorneys pa
        CROSS JOIN generate_series(1, max_week) AS w(week_number)
        LEFT JOIN LATERAL (
            SELECT SUM(settlement_amount) AS total_amount
            FROM settlements s
            WHERE s.attorney_id = pa.attorney_id
              AND EXTRACT(WEEK FROM s.settlement_date)::INT = w.week_number
              AND s.settlement_date BETWEEN start_date AND end_date
        ) s ON TRUE
    ),
    attorney_json AS (
        SELECT 
            attorney_name,
            jsonb_object_agg(
                'Week ' || week_number::TEXT, 
                '$' || COALESCE(TO_CHAR(settlement_amount, 'FM999999999.00'), '0.00')
                ORDER BY week_number DESC
            ) AS weeks_json
        FROM weekly_data
        GROUP BY attorney_name
    )

    -- Final output
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

ALTER FUNCTION public.get_settlement_by_attorneys_weekly(date, date, integer, integer, bigint[])
    OWNER TO postgres;
