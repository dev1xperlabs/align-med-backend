-- FUNCTION: public.get_settlements_by_attorneys(bigint[], text, integer, integer)

-- DROP FUNCTION IF EXISTS public.get_settlements_by_attorneys(bigint[], text, integer, integer);

CREATE OR REPLACE FUNCTION public.get_settlements_by_attorneys(
	p_attorney_ids bigint[] DEFAULT NULL::bigint[],
	p_group_by text DEFAULT 'month'::text,
	p_page_size integer DEFAULT 10,
	p_page_number integer DEFAULT 1)
    RETURNS TABLE(attorney_id integer, attorney_name character varying, settlement_date_formatted text, patient_count bigint, total_billed_charges numeric, total_settlement_amount numeric, avg_settlement_percentage numeric, total_records bigint, current_page integer) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
BEGIN
  RETURN QUERY
  WITH grouped_settlements AS (
    SELECT
      s.attorney_id,
      COALESCE(a.name, 'Unknown Attorney') AS attorney_name,
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
    LEFT JOIN public.attornies a ON s.attorney_id = a.id
    WHERE s.status = B'1'
      AND (p_attorney_ids IS NULL OR s.attorney_id = ANY(p_attorney_ids))
  ),
  final_group AS (
    SELECT
      gs.attorney_id,
      gs.attorney_name,
      CASE 
        WHEN p_group_by = 'week' THEN TO_CHAR(gs.group_date, '"Week "IW, YYYY')
        WHEN p_group_by = 'year' THEN TO_CHAR(gs.group_date, 'YYYY')
        ELSE TO_CHAR(gs.group_date, 'Mon FMDD YYYY')
      END AS settlement_date_formatted,
      COUNT(DISTINCT gs.patient_id) AS patient_count,
      SUM(gs.total_billed_charges) AS total_billed_charges,
      SUM(gs.settlement_amount) AS total_settlement_amount,
      ROUND(AVG(gs.settlement_percentage), 2) AS avg_settlement_percentage
    FROM grouped_settlements gs
    GROUP BY gs.attorney_id, gs.attorney_name, gs.group_date
  ),
  total AS (
    SELECT COUNT(*) AS total_records FROM final_group
  )
  SELECT
    fg.attorney_id,
    fg.attorney_name,
    fg.settlement_date_formatted,
    fg.patient_count,
    fg.total_billed_charges,
    fg.total_settlement_amount,
    fg.avg_settlement_percentage,
    t.total_records,
    p_page_number AS current_page
  FROM final_group fg
  CROSS JOIN total t
  ORDER BY fg.attorney_name, fg.settlement_date_formatted DESC
  LIMIT p_page_size
  OFFSET (p_page_number - 1) * p_page_size;
END;
$BODY$;

ALTER FUNCTION public.get_settlements_by_attorneys(bigint[], text, integer, integer)
    OWNER TO postgres;
