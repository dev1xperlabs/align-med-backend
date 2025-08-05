-- FUNCTION: public.get_settlements_by_date(text, integer, integer)

-- DROP FUNCTION IF EXISTS public.get_settlements_by_date(text, integer, integer);

CREATE OR REPLACE FUNCTION public.get_settlements_by_date(
	p_group_by text DEFAULT 'month'::text,
	p_page_size integer DEFAULT 10,
	p_page_number integer DEFAULT 1)
    RETURNS TABLE(settlement_date_formatted text, patient_count bigint, total_billed_charges numeric, total_settlement_amount numeric, avg_settlement_percentage numeric, total_records bigint, current_page integer) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
BEGIN
    RETURN QUERY
    WITH grouped_settlements AS (
        SELECT
            CASE 
                WHEN p_group_by = 'week' THEN date_trunc('week', s.settlement_date)
                WHEN p_group_by = 'year' THEN date_trunc('year', s.settlement_date)
                ELSE date_trunc('month', s.settlement_date)
            END AS group_date,
            s.patient_id,
            s.total_billed_charges,
            s.settlement_amount,
            s.settlement_percentage
        FROM public.settlements s
        WHERE s.status = B'1'
    ),
    aggregated AS (
        SELECT
            gs.group_date,
            COUNT(gs.patient_id) AS patient_count,
            SUM(gs.total_billed_charges) AS total_billed_charges,
            SUM(gs.settlement_amount) AS total_settlement_amount,
            ROUND(AVG(gs.settlement_percentage), 2) AS avg_settlement_percentage
        FROM grouped_settlements gs
        GROUP BY gs.group_date
    ),
    total_count AS (
        SELECT COUNT(*)::bigint AS total_records FROM aggregated
    )
    SELECT
        CASE 
            WHEN p_group_by = 'week' THEN TO_CHAR(a.group_date, '"Week "IW, YYYY')
            WHEN p_group_by = 'year' THEN TO_CHAR(a.group_date, 'YYYY')
            ELSE TO_CHAR(a.group_date, 'Mon FMDD YYYY')
        END AS settlement_date_formatted,
        a.patient_count,
        a.total_billed_charges,
        a.total_settlement_amount,
        a.avg_settlement_percentage,
        tc.total_records,
        p_page_number AS current_page
    FROM aggregated a
    CROSS JOIN total_count tc
    ORDER BY a.group_date DESC
    LIMIT p_page_size
    OFFSET (p_page_number - 1) * p_page_size;
END;
$BODY$;

ALTER FUNCTION public.get_settlements_by_date(text, integer, integer)
    OWNER TO postgres;
