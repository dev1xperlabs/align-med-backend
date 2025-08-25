-- FUNCTION: public.get_settlement_by_attorneys_daily(date, date, integer, integer, bigint[])

-- DROP FUNCTION IF EXISTS public.get_settlement_by_attorneys_daily(date, date, integer, integer, bigint[]);

CREATE OR REPLACE FUNCTION public.get_settlement_by_attorneys_daily(
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
    -- Count total distinct attorneys in time range (with optional filtering)
    SELECT COUNT(DISTINCT attorney_id)
    INTO total_records
    FROM settlements
    WHERE settlement_date BETWEEN start_date AND end_date
      AND (attorney_ids IS NULL OR attorney_id = ANY(attorney_ids));

    -- CTEs for filtering and pagination
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
    daily_data AS (
        SELECT 
            pa.attorney_name,
            d.visit_date,
            COALESCE(s.total_amount, 0) AS settlement_amount
        FROM paginated_attorneys pa
        CROSS JOIN (
            SELECT generate_series(start_date, end_date, interval '1 day')::DATE AS visit_date
        ) d
        LEFT JOIN LATERAL (
            SELECT SUM(settlement_amount) AS total_amount
            FROM settlements s
            WHERE s.attorney_id = pa.attorney_id
              AND s.settlement_date = d.visit_date
        ) s ON TRUE
    ),
    attorney_json AS (
        SELECT 
            attorney_name,
            jsonb_object_agg(
                TO_CHAR(visit_date, 'MM/DD/YYYY'),
                '$' || TO_CHAR(settlement_amount, 'FM999999999.00')
                ORDER BY visit_date
            ) AS days_json
        FROM daily_data
        GROUP BY attorney_name
    )

    -- Final output
    SELECT jsonb_build_object(
        'data', jsonb_agg(
            jsonb_build_object('attorney', attorney_name) || days_json
        ),
        'totalRecords', total_records,
        'currentPage', page_number
    )
    INTO result
    FROM attorney_json;

    RETURN result;
END;
$BODY$;

ALTER FUNCTION public.get_settlement_by_attorneys_daily(date, date, integer, integer, bigint[])
    OWNER TO postgres;
