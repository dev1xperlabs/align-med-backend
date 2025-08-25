-- FUNCTION: public.get_settlements_billing_test()

-- DROP FUNCTION IF EXISTS public.get_settlements_billing_test();

CREATE OR REPLACE FUNCTION public.get_settlements_billing(
	)
    RETURNS TABLE(total_billed_today numeric, total_billed_this_week numeric, total_billed_this_month numeric, total_billed_this_year numeric, percentage_today numeric, percentage_week numeric, percentage_month numeric, percentage_year numeric, trend_today text, trend_week text, trend_month text, trend_year text) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
DECLARE
    -- Today and Yesterday
    today_total NUMERIC;
    yesterday_total NUMERIC;

    -- Week
    week_start DATE := date_trunc('week', CURRENT_DATE)::DATE;
    this_week_total NUMERIC;
    last_week_start DATE := week_start - INTERVAL '7 days';
    last_week_end DATE := week_start - INTERVAL '1 day';
    last_week_total NUMERIC;

    -- Month
    month_start DATE := date_trunc('month', CURRENT_DATE)::DATE;
    this_month_total NUMERIC;
    last_month_start DATE := (month_start - INTERVAL '1 month')::DATE;
    last_month_end DATE := (month_start - INTERVAL '1 day')::DATE;
    last_month_total NUMERIC;

    -- Year
    year_start DATE := date_trunc('year', CURRENT_DATE)::DATE;
    this_year_total NUMERIC;
    last_year_start DATE := (year_start - INTERVAL '1 year')::DATE;
    last_year_end DATE := (year_start - INTERVAL '1 day')::DATE;
    last_year_total NUMERIC;

    -- Percentage changes
    pct_today NUMERIC;
    pct_week NUMERIC;
    pct_month NUMERIC;
    pct_year NUMERIC;

    -- Trends
    tr_today TEXT;
    tr_week TEXT;
    tr_month TEXT;
    tr_year TEXT;
BEGIN
    -- Today & Yesterday
    SELECT
        COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date::DATE = CURRENT_DATE), 0),
        COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date::DATE = CURRENT_DATE - INTERVAL '1 day'), 0)
    INTO today_total, yesterday_total
    FROM public.settlements;

    -- This Week & Last Week
    SELECT
        COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date::DATE >= week_start AND settlement_date::DATE <= CURRENT_DATE), 0),
        COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date::DATE >= last_week_start AND settlement_date::DATE <= last_week_end), 0)
    INTO this_week_total, last_week_total
    FROM public.settlements;

    -- This Month & Last Month
    SELECT
        COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date::DATE >= month_start AND settlement_date::DATE <= CURRENT_DATE), 0),
        COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date::DATE >= last_month_start AND settlement_date::DATE <= last_month_end), 0)
    INTO this_month_total, last_month_total
    FROM public.settlements;

    -- This Year & Last Year
    SELECT
        COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date::DATE >= year_start AND settlement_date::DATE <= CURRENT_DATE), 0),
        COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date::DATE >= last_year_start AND settlement_date::DATE <= last_year_end), 0)
    INTO this_year_total, last_year_total
    FROM public.settlements;

    -- Percentages (rounded to 2 decimals)
    pct_today := CASE WHEN yesterday_total = 0 THEN NULL ELSE ROUND(((today_total - yesterday_total) * 100.0 / yesterday_total), 2) END;
    pct_week := CASE WHEN last_week_total = 0 THEN NULL ELSE ROUND(((this_week_total - last_week_total) * 100.0 / last_week_total), 2) END;
    pct_month := CASE WHEN last_month_total = 0 THEN NULL ELSE ROUND(((this_month_total - last_month_total) * 100.0 / last_month_total), 2) END;
    pct_year := CASE WHEN last_year_total = 0 THEN NULL ELSE ROUND(((this_year_total - last_year_total) * 100.0 / last_year_total), 2) END;

    -- Trends
    tr_today := CASE
        WHEN pct_today IS NULL THEN 'neutral'
        WHEN pct_today > 0 THEN 'up'
        WHEN pct_today < 0 THEN 'down'
        ELSE 'neutral'
    END;

    tr_week := CASE
        WHEN pct_week IS NULL THEN 'neutral'
        WHEN pct_week > 0 THEN 'up'
        WHEN pct_week < 0 THEN 'down'
        ELSE 'neutral'
    END;

    tr_month := CASE
        WHEN pct_month IS NULL THEN 'neutral'
        WHEN pct_month > 0 THEN 'up'
        WHEN pct_month < 0 THEN 'down'
        ELSE 'neutral'
    END;

    tr_year := CASE
        WHEN pct_year IS NULL THEN 'neutral'
        WHEN pct_year > 0 THEN 'up'
        WHEN pct_year < 0 THEN 'down'
        ELSE 'neutral'
    END;

    -- Return Result
    RETURN QUERY
    SELECT
        today_total,
        this_week_total,
        this_month_total,
        this_year_total,
        pct_today,
        pct_week,
        pct_month,
        pct_year,
        tr_today,
        tr_week,
        tr_month,
        tr_year;
END;
$BODY$;