-- FUNCTION: public.get_attorney_bonus_summary(date, date, integer)

-- DROP FUNCTION IF EXISTS public.get_attorney_bonus_summary(date, date, integer);

CREATE OR REPLACE FUNCTION public.get_attorney_bonus_summary(
	p_from_date date,
	p_to_date date,
	p_rule_id integer)
    RETURNS TABLE(rule_id integer, rule_name text, provider_id integer, attorney_name text, bonus_percentage numeric, attorney_id integer, billed_date text, total_billed_charges numeric, bonus_amount numeric) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
DECLARE
    v_provider_id INT;
BEGIN
    -- Step 1: Get provider_id for the rule
    SELECT r.provider_id INTO v_provider_id
    FROM public.rules r
    WHERE r.id = p_rule_id;

    -- Step 2: Main logic
    RETURN QUERY
    WITH selected_attorneys AS (
        SELECT ram.attorney_id
        FROM public.rule_attorneys_mapping ram
        WHERE ram.rule_id = p_rule_id
    ),
    filtered_bills AS (
        SELECT *
        FROM public.bills b
        WHERE 
            b.billed_date BETWEEN p_from_date AND p_to_date
            AND b.provider_id = v_provider_id
            AND b.attorney_id IN (SELECT sa.attorney_id FROM selected_attorneys sa)
    ),
    summed_bills AS (
        SELECT 
            fb.attorney_id,
            MAX(fb.billed_date) AS billed_date,
            SUM(fb.total_billed_charges) AS total_billed_charges
        FROM filtered_bills fb
        GROUP BY fb.attorney_id
    ),
    selected_rule AS (
        SELECT *
        FROM public.rules
        WHERE id = p_rule_id
    )
    SELECT
        r.id AS rule_id,
        r.rule_name::TEXT,
        r.provider_id,
        a.name::TEXT AS attorney_name,
        r.bonus_percentage,
        sb.attorney_id,
        TO_CHAR(sb.billed_date, 'DD/MM/YYYY') AS billed_date,
        sb.total_billed_charges,
        ROUND((r.bonus_percentage / 100.0) * sb.total_billed_charges, 2) AS bonus_amount
    FROM summed_bills sb
    JOIN public.attornies a ON sb.attorney_id = a.id
    CROSS JOIN selected_rule r;
END;
$BODY$;

ALTER FUNCTION public.get_attorney_bonus_summary(date, date, integer)
    OWNER TO postgres;
