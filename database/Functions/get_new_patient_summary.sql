-- FUNCTION: public.get_new_patient_summary_test()

-- DROP FUNCTION IF EXISTS public.get_new_patient_summary_test();

CREATE OR REPLACE FUNCTION public.get_new_patient_summary(
	)
    RETURNS TABLE(new_patients_today integer, new_patients_this_week integer, new_patients_this_month integer, new_patients_this_year integer, percentage_today numeric, percentage_week numeric, percentage_month numeric, percentage_year numeric, trend_today text, trend_week text, trend_month text, trend_year text) 
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
DECLARE
    today_count INTEGER;
    yesterday_count INTEGER;

    week_start DATE := date_trunc('week', CURRENT_DATE)::DATE;
    week_count INTEGER;
    last_week_start DATE := week_start - INTERVAL '7 days';
    last_week_end DATE := week_start - INTERVAL '1 day';
    last_week_count INTEGER;

    month_start DATE := date_trunc('month', CURRENT_DATE)::DATE;
    month_count INTEGER;
    last_month_start DATE := (month_start - INTERVAL '1 month')::DATE;
    last_month_end DATE := (month_start - INTERVAL '1 day')::DATE;
    last_month_count INTEGER;

    year_start DATE := date_trunc('year', CURRENT_DATE)::DATE;
    year_count INTEGER;
    last_year_start DATE := (year_start - INTERVAL '1 year')::DATE;
    last_year_end DATE := (year_start - INTERVAL '1 day')::DATE;
    last_year_count INTEGER;

    pct_today NUMERIC;
    pct_week NUMERIC;
    pct_month NUMERIC;
    pct_year NUMERIC;

    tr_today TEXT;
    tr_week TEXT;
    tr_month TEXT;
    tr_year TEXT;
BEGIN
    -- Today and Yesterday
    SELECT
        COUNT(*) FILTER (WHERE first_visit_date::DATE = CURRENT_DATE),
        COUNT(*) FILTER (WHERE first_visit_date::DATE = CURRENT_DATE - INTERVAL '1 day')
    INTO today_count, yesterday_count
    FROM public.patient_location_log;

    -- This Week and Last Week
    SELECT
        COUNT(*) FILTER (WHERE first_visit_date::DATE >= week_start AND first_visit_date::DATE <= CURRENT_DATE),
        COUNT(*) FILTER (WHERE first_visit_date::DATE >= last_week_start AND first_visit_date::DATE <= last_week_end)
    INTO week_count, last_week_count
    FROM public.patient_location_log;

    -- This Month and Last Month
    SELECT
        COUNT(*) FILTER (WHERE first_visit_date::DATE >= month_start AND first_visit_date::DATE <= CURRENT_DATE),
        COUNT(*) FILTER (WHERE first_visit_date::DATE >= last_month_start AND first_visit_date::DATE <= last_month_end)
    INTO month_count, last_month_count
    FROM public.patient_location_log;

    -- This Year and Last Year
    SELECT
        COUNT(*) FILTER (WHERE first_visit_date::DATE >= year_start AND first_visit_date::DATE <= CURRENT_DATE),
        COUNT(*) FILTER (WHERE first_visit_date::DATE >= last_year_start AND first_visit_date::DATE <= last_year_end)
    INTO year_count, last_year_count
    FROM public.patient_location_log;

    -- Percentages
    pct_today := CASE WHEN yesterday_count = 0 THEN NULL ELSE ROUND(((today_count - yesterday_count) * 100.0 / yesterday_count), 2) END;
pct_week := CASE WHEN last_week_count = 0 THEN NULL ELSE ROUND(((week_count - last_week_count) * 100.0 / last_week_count), 2) END;
pct_month := CASE WHEN last_month_count = 0 THEN NULL ELSE ROUND(((month_count - last_month_count) * 100.0 / last_month_count), 2) END;
pct_year := CASE WHEN last_year_count = 0 THEN NULL ELSE ROUND(((year_count - last_year_count) * 100.0 / last_year_count), 2) END;

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

    -- Final Return
    RETURN QUERY
    SELECT
        today_count,
        week_count,
        month_count,
        year_count,
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
