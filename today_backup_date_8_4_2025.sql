--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5
-- Dumped by pg_dump version 17.5

-- Started on 2025-08-04 14:36:53

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 257 (class 1255 OID 90953)
-- Name: get_attorney_bonus_summary(date, date, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_attorney_bonus_summary(p_from_date date, p_to_date date, p_rule_id integer) RETURNS TABLE(rule_id integer, rule_name text, provider_id integer, attorney_name text, bonus_percentage numeric, attorney_id integer, billed_date text, total_billed_charges numeric, bonus_amount numeric)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_attorney_bonus_summary(p_from_date date, p_to_date date, p_rule_id integer) OWNER TO postgres;

--
-- TOC entry 256 (class 1255 OID 90952)
-- Name: get_billing_summary(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_billing_summary() RETURNS TABLE(total_billed_today numeric, total_billed_this_week numeric, total_billed_this_month numeric, total_billed_this_year numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    COALESCE(SUM(total_billed_charges) FILTER (WHERE billed_date::DATE = CURRENT_DATE), 0)::NUMERIC AS total_billed_today,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE billed_date >= date_trunc('week', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_week,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE billed_date >= date_trunc('month', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_month,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE billed_date >= date_trunc('year', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_year
  FROM public.bills
  WHERE billed_date IS NOT NULL;
END;
$$;


ALTER FUNCTION public.get_billing_summary() OWNER TO postgres;

--
-- TOC entry 260 (class 1255 OID 90951)
-- Name: get_count_of_new_patients_by_location(integer, integer, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_count_of_new_patients_by_location(p_page_size integer DEFAULT 10, p_page_number integer DEFAULT 1, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date) RETURNS TABLE(visit_date text, location_id bigint, location_name character varying, patient_count bigint, total_records bigint, current_page integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH filtered_data AS (
        SELECT 
            l.first_visit_date,
            l.location_id,
            ls.name AS location_name
        FROM public.patient_location_log l
        LEFT JOIN public.locations ls ON l.location_id = ls.id
        WHERE (p_start_date IS NULL OR l.first_visit_date >= p_start_date)
          AND (p_end_date IS NULL OR l.first_visit_date <= p_end_date)
    ),
    -- Step 1: Get distinct first_visit_dates, ordered descending, then paginate them
    paginated_dates AS (
        SELECT DISTINCT first_visit_date
        FROM filtered_data
        ORDER BY first_visit_date DESC
        LIMIT p_page_size
        OFFSET (p_page_number - 1) * p_page_size
    ),
    -- Step 2: Join back to get all data for selected dates
    grouped_data AS (
        SELECT 
            fd.first_visit_date,
            fd.location_id,
            fd.location_name,
            COUNT(*)::bigint AS patient_count
        FROM filtered_data fd
        JOIN paginated_dates pd ON fd.first_visit_date = pd.first_visit_date
        GROUP BY fd.first_visit_date, fd.location_id, fd.location_name
    ),
    -- Step 3: Get total distinct dates count for pagination
    total_count AS (
        SELECT COUNT(DISTINCT first_visit_date)::bigint AS total FROM filtered_data
    )
    SELECT 
        TO_CHAR(gd.first_visit_date + INTERVAL '3 days', 'FMMM/FMDD/YYYY') AS visit_date,
        gd.location_id,
        gd.location_name,
        gd.patient_count,
        tc.total,
        p_page_number
    FROM grouped_data gd
    CROSS JOIN total_count tc
    ORDER BY gd.first_visit_date DESC, gd.location_id;
END;
$$;


ALTER FUNCTION public.get_count_of_new_patients_by_location(p_page_size integer, p_page_number integer, p_start_date date, p_end_date date) OWNER TO postgres;

--
-- TOC entry 261 (class 1255 OID 90955)
-- Name: get_count_of_patients_by_attorney(bigint[], integer, integer, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_count_of_patients_by_attorney(p_attorney_ids bigint[] DEFAULT NULL::bigint[], p_page_size integer DEFAULT 10, p_page_number integer DEFAULT 1, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date) RETURNS TABLE(visit_date text, attorney_id bigint, attorney_name character varying, patient_count bigint, total_records bigint, current_page integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN QUERY
	WITH filtered_data AS (
		SELECT 
			pal.first_visit_date::DATE AS raw_visit_date,
			pal.attorney_id,
			a.name AS attorney_name,
			COUNT(pal.patient_id)::BIGINT as patient_count
		FROM public.patient_attorny_log pal
		LEFT JOIN public.attornies a ON pal.attorney_id = a.id
		WHERE pal.first_visit_date IS NOT NULL
			AND (p_start_date IS NULL OR pal.first_visit_date >= p_start_date)
			AND (p_end_date IS NULL OR pal.first_visit_date <= p_end_date)
			AND (p_attorney_ids IS NULL OR pal.attorney_id = ANY(p_attorney_ids))
		GROUP BY pal.first_visit_date, pal.attorney_id, a.name
	),
	total_count AS (
		SELECT COUNT(*)::BIGINT AS total FROM filtered_data
	)
	SELECT 
		TO_CHAR(fd.raw_visit_date, 'FMMM/FMDD/YYYY') AS visit_date,
		fd.attorney_id,
		fd.attorney_name,
		fd.patient_count,
		tc.total AS total_records,
		p_page_number AS current_page
	FROM filtered_data fd
	CROSS JOIN total_count tc
	ORDER BY fd.raw_visit_date DESC, fd.attorney_id
	LIMIT p_page_size
	OFFSET (p_page_number - 1) * p_page_size;
END;
$$;


ALTER FUNCTION public.get_count_of_patients_by_attorney(p_attorney_ids bigint[], p_page_size integer, p_page_number integer, p_start_date date, p_end_date date) OWNER TO postgres;

--
-- TOC entry 262 (class 1255 OID 90963)
-- Name: get_count_of_patients_by_attorney_jj(bigint[], integer, integer, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_count_of_patients_by_attorney_jj(p_attorney_ids bigint[] DEFAULT NULL::bigint[], p_page_size integer DEFAULT 10, p_page_number integer DEFAULT 1, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date) RETURNS TABLE(visit_date text, attorney_id bigint, attorney_name character varying, patient_count bigint, total_records bigint, current_page integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH base_data AS (
        SELECT 
            pal.first_visit_date::date AS raw_visit_date,
            pal.attorney_id,
            a.name AS attorney_name
        FROM public.patient_attorny_log pal
        LEFT JOIN public.attornies a ON pal.attorney_id = a.id
        WHERE pal.first_visit_date IS NOT NULL
            AND (p_start_date IS NULL OR pal.first_visit_date >= p_start_date)
            AND (p_end_date IS NULL OR pal.first_visit_date <= p_end_date)
            AND (p_attorney_ids IS NULL OR pal.attorney_id = ANY(p_attorney_ids))
    ),

    -- Step 1: Get distinct attorneys
    distinct_attorneys AS (
        SELECT DISTINCT attorney_id, attorney_name
        FROM base_data
    ),

    -- Step 2: Paginate attorneys
    paginated_attorneys AS (
        SELECT *
        FROM distinct_attorneys
        ORDER BY attorney_id
        LIMIT p_page_size
        OFFSET (p_page_number - 1) * p_page_size
    ),

    -- Step 3: Join back to get all visit-date level rows for those attorneys
    filtered_data AS (
        SELECT 
            bd.raw_visit_date,
            bd.attorney_id,
            bd.attorney_name
        FROM base_data bd
        JOIN paginated_attorneys pa ON bd.attorney_id = pa.attorney_id
    ),

    -- Step 4: Group by visit_date and attorney
    grouped_data AS (
        SELECT 
            fd.raw_visit_date,
            fd.attorney_id,
            fd.attorney_name,
            COUNT(*)::bigint AS patient_count
        FROM filtered_data fd
        GROUP BY fd.raw_visit_date, fd.attorney_id, fd.attorney_name
    ),

    -- Step 5: Get total distinct attorneys count
    total_count AS (
        SELECT COUNT(*)::bigint AS total FROM distinct_attorneys
    )

    SELECT 
        TO_CHAR(gd.raw_visit_date, 'FMMM/FMDD/YYYY') AS visit_date,
        gd.attorney_id,
        gd.attorney_name,
        gd.patient_count,
        tc.total AS total_records,
        p_page_number AS current_page
    FROM grouped_data gd
    CROSS JOIN total_count tc
    ORDER BY gd.raw_visit_date DESC, gd.attorney_id;
END;
$$;


ALTER FUNCTION public.get_count_of_patients_by_attorney_jj(p_attorney_ids bigint[], p_page_size integer, p_page_number integer, p_start_date date, p_end_date date) OWNER TO postgres;

--
-- TOC entry 242 (class 1255 OID 90949)
-- Name: get_new_patient_summary(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_new_patient_summary() RETURNS TABLE(new_patients_today integer, new_patients_this_week integer, new_patients_this_month integer, new_patients_this_year integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    COUNT(*) FILTER (WHERE first_visit_date::DATE = CURRENT_DATE)::INTEGER AS new_patients_today,
    COUNT(*) FILTER (WHERE first_visit_date >= date_trunc('week', CURRENT_DATE))::INTEGER AS new_patients_this_week,
    COUNT(*) FILTER (WHERE first_visit_date >= date_trunc('month', CURRENT_DATE))::INTEGER AS new_patients_this_month,
    COUNT(*) FILTER (WHERE first_visit_date >= date_trunc('year', CURRENT_DATE))::INTEGER AS new_patients_this_year
  FROM public.patient_location_log
  WHERE created_at IS NOT NULL;
END;
$$;


ALTER FUNCTION public.get_new_patient_summary() OWNER TO postgres;

--
-- TOC entry 241 (class 1255 OID 90948)
-- Name: get_settlements_billing(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_settlements_billing() RETURNS TABLE(total_billed_today numeric, total_billed_this_week numeric, total_billed_this_month numeric, total_billed_this_year numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
  SELECT
    COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date::DATE = CURRENT_DATE), 0)::NUMERIC AS total_billed_today,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date >= date_trunc('week', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_week,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date >= date_trunc('month', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_month,
    COALESCE(SUM(total_billed_charges) FILTER (WHERE settlement_date >= date_trunc('year', CURRENT_DATE)), 0)::NUMERIC AS total_billed_this_year
  FROM public.settlements
  WHERE settlement_date IS NOT NULL;
END;
$$;


ALTER FUNCTION public.get_settlements_billing() OWNER TO postgres;

--
-- TOC entry 255 (class 1255 OID 90947)
-- Name: get_settlements_by_attorneys(bigint[], text, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_settlements_by_attorneys(p_attorney_ids bigint[] DEFAULT NULL::bigint[], p_group_by text DEFAULT 'month'::text, p_page_size integer DEFAULT 10, p_page_number integer DEFAULT 1) RETURNS TABLE(attorney_id integer, attorney_name character varying, settlement_date_formatted text, patient_count bigint, total_billed_charges numeric, total_settlement_amount numeric, avg_settlement_percentage numeric, total_records bigint, current_page integer)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_settlements_by_attorneys(p_attorney_ids bigint[], p_group_by text, p_page_size integer, p_page_number integer) OWNER TO postgres;

--
-- TOC entry 254 (class 1255 OID 90946)
-- Name: get_settlements_by_date(text, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_settlements_by_date(p_group_by text DEFAULT 'month'::text, p_page_size integer DEFAULT 10, p_page_number integer DEFAULT 1) RETURNS TABLE(settlement_date_formatted text, patient_count bigint, total_billed_charges numeric, total_settlement_amount numeric, avg_settlement_percentage numeric, total_records bigint, current_page integer)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_settlements_by_date(p_group_by text, p_page_size integer, p_page_number integer) OWNER TO postgres;

--
-- TOC entry 259 (class 1255 OID 90956)
-- Name: get_sum_of_billed_charges_by_attorney(bigint[], integer, integer, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_sum_of_billed_charges_by_attorney(p_attorney_ids bigint[] DEFAULT NULL::bigint[], p_page_size integer DEFAULT 10, p_page_number integer DEFAULT 1, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date) RETURNS TABLE(billed_date text, attorney_id bigint, attorney_name character varying, total_billed_charges numeric, total_records bigint, current_page integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH filtered_data AS (
        SELECT 
            b.billed_date::DATE AS raw_billed_date,
            b.attorney_id::BIGINT,
            COALESCE(a.name, 'Unknown Attorney') AS attorney_name,
            SUM(b.total_billed_charges)::NUMERIC AS total_billed_charges
        FROM public.bills b
        LEFT JOIN public.attornies a ON b.attorney_id = a.id
        WHERE 
            b.billed_date IS NOT NULL -- ✅ remove null dates
            AND (p_start_date IS NULL OR b.billed_date >= p_start_date)
            AND (p_end_date IS NULL OR b.billed_date <= p_end_date)
            AND (p_attorney_ids IS NULL OR b.attorney_id = ANY(p_attorney_ids))
            AND b.attorney_id IS NOT NULL
        GROUP BY b.billed_date, b.attorney_id, a.name
        HAVING SUM(b.total_billed_charges) > 0
    ),
    total_count AS (
        SELECT COUNT(*)::BIGINT AS total FROM filtered_data
    )
    SELECT 
        TO_CHAR(fd.raw_billed_date, 'MM/DD/YYYY') AS billed_date, -- ✅ format as string
        fd.attorney_id,
        fd.attorney_name,
        fd.total_billed_charges,
        tc.total AS total_records,
        p_page_number AS current_page
    FROM filtered_data fd
    CROSS JOIN total_count tc
    ORDER BY fd.raw_billed_date DESC, total_billed_charges DESC, attorney_id
    LIMIT p_page_size
    OFFSET (p_page_number - 1) * p_page_size;
END;
$$;


ALTER FUNCTION public.get_sum_of_billed_charges_by_attorney(p_attorney_ids bigint[], p_page_size integer, p_page_number integer, p_start_date date, p_end_date date) OWNER TO postgres;

--
-- TOC entry 258 (class 1255 OID 90944)
-- Name: get_sum_of_new_patients_by_location(integer, integer, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_sum_of_new_patients_by_location(p_page_size integer DEFAULT 10, p_page_number integer DEFAULT 1, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date) RETURNS TABLE(visit_date text, location_id bigint, location_name character varying, total_revenue numeric, total_patient_visits bigint, total_records bigint, current_page integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH filtered_data AS (
        SELECT 
            COALESCE(b.location_id, pl.location_id) AS location_id,
            pl.first_visit_date,
            b.patient_id,
            b.total_billed_charges
        FROM public.bills b
        LEFT JOIN public.patient_location_log pl 
            ON b.patient_id = pl.patient_id
        WHERE (p_start_date IS NULL OR pl.first_visit_date >= p_start_date)
          AND (p_end_date IS NULL OR pl.first_visit_date <= p_end_date)
    ),
    aggregated AS (
        SELECT
            f.first_visit_date,
            f.location_id,
            COALESCE(l.name, 'Unknown Location') AS location_name,
            SUM(f.total_billed_charges)::NUMERIC AS total_revenue,
            COUNT(DISTINCT f.patient_id)::BIGINT AS total_patient_visits
        FROM filtered_data f
        LEFT JOIN public.locations l ON f.location_id = l.id
        GROUP BY f.first_visit_date, f.location_id, l.name
        HAVING SUM(f.total_billed_charges) > 0
    ),
    total_count AS (
        SELECT COUNT(*)::bigint AS total FROM aggregated
    )
    SELECT 
        TO_CHAR(a.first_visit_date, 'FMMM/FMDD/YYYY') AS visit_date,
        a.location_id,
        a.location_name,
        a.total_revenue,
        a.total_patient_visits,
        tc.total AS total_records,
        p_page_number AS current_page
    FROM aggregated a
    CROSS JOIN total_count tc
    ORDER BY a.first_visit_date DESC, a.location_id
    LIMIT p_page_size
    OFFSET (p_page_number - 1) * p_page_size;
END;
$$;


ALTER FUNCTION public.get_sum_of_new_patients_by_location(p_page_size integer, p_page_number integer, p_start_date date, p_end_date date) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 217 (class 1259 OID 90757)
-- Name: attornies; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.attornies (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    phone_number character varying(20),
    status bit(1) DEFAULT '1'::"bit" NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


ALTER TABLE public.attornies OWNER TO postgres;

--
-- TOC entry 218 (class 1259 OID 90761)
-- Name: attornies_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.attornies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.attornies_id_seq OWNER TO postgres;

--
-- TOC entry 4957 (class 0 OID 0)
-- Dependencies: 218
-- Name: attornies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.attornies_id_seq OWNED BY public.attornies.id;


--
-- TOC entry 219 (class 1259 OID 90762)
-- Name: bills; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bills (
    id bigint NOT NULL,
    patient_id integer,
    attorney_id integer NOT NULL,
    location_id integer,
    billed_date date NOT NULL,
    total_billed_charges numeric(18,2) NOT NULL,
    status bit(1) DEFAULT '1'::"bit" NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    provider_id integer
);


ALTER TABLE public.bills OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 90766)
-- Name: bills_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.bills_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.bills_id_seq OWNER TO postgres;

--
-- TOC entry 4958 (class 0 OID 0)
-- Dependencies: 220
-- Name: bills_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.bills_id_seq OWNED BY public.bills.id;


--
-- TOC entry 221 (class 1259 OID 90767)
-- Name: locations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.locations (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    status bit(1) DEFAULT '1'::"bit" NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


ALTER TABLE public.locations OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 90771)
-- Name: locations_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.locations_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.locations_id_seq OWNER TO postgres;

--
-- TOC entry 4959 (class 0 OID 0)
-- Dependencies: 222
-- Name: locations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.locations_id_seq OWNED BY public.locations.id;


--
-- TOC entry 223 (class 1259 OID 90772)
-- Name: patient_attorny_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.patient_attorny_log (
    id bigint NOT NULL,
    patient_id bigint NOT NULL,
    attorney_id bigint NOT NULL,
    first_visit_date date NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    location_id integer,
    last_visit_date date
);


ALTER TABLE public.patient_attorny_log OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 90777)
-- Name: patient_attorny_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.patient_attorny_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.patient_attorny_log_id_seq OWNER TO postgres;

--
-- TOC entry 4960 (class 0 OID 0)
-- Dependencies: 224
-- Name: patient_attorny_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.patient_attorny_log_id_seq OWNED BY public.patient_attorny_log.id;


--
-- TOC entry 225 (class 1259 OID 90778)
-- Name: patient_location_log; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.patient_location_log (
    id bigint NOT NULL,
    patient_id bigint NOT NULL,
    location_id bigint NOT NULL,
    first_visit_date date NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now(),
    last_visit_date date NOT NULL
);


ALTER TABLE public.patient_location_log OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 90783)
-- Name: patient_location_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.patient_location_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.patient_location_log_id_seq OWNER TO postgres;

--
-- TOC entry 4961 (class 0 OID 0)
-- Dependencies: 226
-- Name: patient_location_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.patient_location_log_id_seq OWNED BY public.patient_location_log.id;


--
-- TOC entry 227 (class 1259 OID 90784)
-- Name: patients; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.patients (
    id integer NOT NULL,
    external_mrn character varying(10) NOT NULL,
    first_name character varying(255) NOT NULL,
    middle_name character varying(255),
    last_name character varying(255),
    dob date,
    email character varying(255),
    phone_number character varying(20),
    status bit(1) DEFAULT '1'::"bit" NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    gender character varying(10)
);


ALTER TABLE public.patients OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 90790)
-- Name: patients_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.patients_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.patients_id_seq OWNER TO postgres;

--
-- TOC entry 4962 (class 0 OID 0)
-- Dependencies: 228
-- Name: patients_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.patients_id_seq OWNED BY public.patients.id;


--
-- TOC entry 229 (class 1259 OID 90791)
-- Name: providers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.providers (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    status bit(1) DEFAULT '1'::"bit" NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


ALTER TABLE public.providers OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 90795)
-- Name: providers_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.providers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.providers_id_seq OWNER TO postgres;

--
-- TOC entry 4963 (class 0 OID 0)
-- Dependencies: 230
-- Name: providers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.providers_id_seq OWNED BY public.providers.id;


--
-- TOC entry 231 (class 1259 OID 90796)
-- Name: refresh_tokens; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.refresh_tokens (
    id integer NOT NULL,
    user_id integer NOT NULL,
    token character varying(255) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.refresh_tokens OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 90800)
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.refresh_tokens ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 233 (class 1259 OID 90801)
-- Name: rule_attorneys_mapping; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rule_attorneys_mapping (
    id integer NOT NULL,
    rule_id integer NOT NULL,
    attorney_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now(),
    updated_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.rule_attorneys_mapping OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 90806)
-- Name: rule_attorneys_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.rule_attorneys_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rule_attorneys_mapping_id_seq OWNER TO postgres;

--
-- TOC entry 4964 (class 0 OID 0)
-- Dependencies: 234
-- Name: rule_attorneys_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.rule_attorneys_mapping_id_seq OWNED BY public.rule_attorneys_mapping.id;


--
-- TOC entry 235 (class 1259 OID 90807)
-- Name: rules; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.rules (
    id integer NOT NULL,
    provider_id integer NOT NULL,
    bonus_percentage numeric(18,2) NOT NULL,
    status bit(1) DEFAULT '1'::"bit" NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    rule_name character varying(255) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE public.rules OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 90812)
-- Name: rules_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.rules_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.rules_id_seq OWNER TO postgres;

--
-- TOC entry 4965 (class 0 OID 0)
-- Dependencies: 236
-- Name: rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.rules_id_seq OWNED BY public.rules.id;


--
-- TOC entry 237 (class 1259 OID 90813)
-- Name: settlements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.settlements (
    id integer NOT NULL,
    patient_id integer,
    attorney_id integer,
    settlement_date date NOT NULL,
    total_billed_charges numeric(18,2) NOT NULL,
    status bit(1) DEFAULT '1'::"bit" NOT NULL,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    settlement_percentage numeric(18,2),
    settlement_amount numeric(18,2) NOT NULL
);


ALTER TABLE public.settlements OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 90817)
-- Name: selttlements_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.selttlements_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.selttlements_id_seq OWNER TO postgres;

--
-- TOC entry 4966 (class 0 OID 0)
-- Dependencies: 238
-- Name: selttlements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.selttlements_id_seq OWNED BY public.settlements.id;


--
-- TOC entry 239 (class 1259 OID 90818)
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    first_name character varying(255) NOT NULL,
    last_name character varying(255) NOT NULL,
    email character varying(255) NOT NULL,
    password_hash character varying(255) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    phone_number bigint,
    status bit(1) DEFAULT '1'::"bit" NOT NULL
);


ALTER TABLE public.users OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 90826)
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_id_seq OWNER TO postgres;

--
-- TOC entry 4967 (class 0 OID 0)
-- Dependencies: 240
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- TOC entry 4707 (class 2604 OID 90827)
-- Name: attornies id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attornies ALTER COLUMN id SET DEFAULT nextval('public.attornies_id_seq'::regclass);


--
-- TOC entry 4709 (class 2604 OID 90828)
-- Name: bills id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bills ALTER COLUMN id SET DEFAULT nextval('public.bills_id_seq'::regclass);


--
-- TOC entry 4711 (class 2604 OID 90829)
-- Name: locations id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.locations ALTER COLUMN id SET DEFAULT nextval('public.locations_id_seq'::regclass);


--
-- TOC entry 4713 (class 2604 OID 90830)
-- Name: patient_attorny_log id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_attorny_log ALTER COLUMN id SET DEFAULT nextval('public.patient_attorny_log_id_seq'::regclass);


--
-- TOC entry 4716 (class 2604 OID 90831)
-- Name: patient_location_log id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_location_log ALTER COLUMN id SET DEFAULT nextval('public.patient_location_log_id_seq'::regclass);


--
-- TOC entry 4719 (class 2604 OID 90832)
-- Name: patients id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patients ALTER COLUMN id SET DEFAULT nextval('public.patients_id_seq'::regclass);


--
-- TOC entry 4721 (class 2604 OID 90833)
-- Name: providers id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.providers ALTER COLUMN id SET DEFAULT nextval('public.providers_id_seq'::regclass);


--
-- TOC entry 4724 (class 2604 OID 90834)
-- Name: rule_attorneys_mapping id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rule_attorneys_mapping ALTER COLUMN id SET DEFAULT nextval('public.rule_attorneys_mapping_id_seq'::regclass);


--
-- TOC entry 4727 (class 2604 OID 90835)
-- Name: rules id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rules ALTER COLUMN id SET DEFAULT nextval('public.rules_id_seq'::regclass);


--
-- TOC entry 4732 (class 2604 OID 90836)
-- Name: settlements id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.settlements ALTER COLUMN id SET DEFAULT nextval('public.selttlements_id_seq'::regclass);


--
-- TOC entry 4734 (class 2604 OID 90837)
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- TOC entry 4928 (class 0 OID 90757)
-- Dependencies: 217
-- Data for Name: attornies; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.attornies (id, name, phone_number, status, created_at, updated_at) FROM stdin;
43	Ace Lakhani Law Firm	702-814-4000	1	2025-08-03 19:21:56.617866	2025-08-03 19:21:56.617876
44	Adam Kutner	\N	1	2025-08-03 19:21:57.255699	2025-08-03 19:21:57.255704
45	Benson & Bingham	702-382-9797	1	2025-08-03 19:21:57.985539	2025-08-03 19:21:57.985546
46	Eric K Chen	702-638-8886	1	2025-08-03 19:21:58.496347	2025-08-03 19:21:58.496352
47	Hicks & Brasier	\N	1	2025-08-03 19:21:59.145353	2025-08-03 19:21:59.145356
48	Morris Injury Law	855-667-7529	1	2025-08-03 19:21:59.588916	2025-08-03 19:21:59.58892
49	Nevada Legal Group	702-538-7824	1	2025-08-03 19:22:00.076144	2025-08-03 19:22:00.076152
50	Richard Harris Law Firm	702-550-7537	1	2025-08-03 19:22:00.521096	2025-08-03 19:22:00.521104
51	Shook & Stone	\N	1	2025-08-03 19:22:01.232116	2025-08-03 19:22:01.232123
52	The Cottner Firm	702-382-1170	1	2025-08-03 19:22:01.7806	2025-08-03 19:22:01.780618
53	Vegas Valley Injury Law	702-444-5555	1	2025-08-03 19:22:02.497237	2025-08-03 19:22:02.497243
54	Ace Law Group	702-333-4223	1	2025-08-03 19:22:02.920506	2025-08-03 19:22:02.920509
55	Paul Padda Law	702-366-1888	1	2025-08-03 19:22:05.738764	2025-08-03 19:22:05.73877
56	The Firm LA, PC	\N	1	2025-08-03 19:22:06.175753	2025-08-03 19:22:06.175774
57	The Powell Law Firm TPLF	\N	1	2025-08-03 19:22:07.019576	2025-08-03 19:22:07.019581
58	Karns & Karns	310-623-9032	1	2025-08-03 19:22:11.209173	2025-08-03 19:22:11.209202
59	The Big Guns Law	702-500-4867	1	2025-08-03 19:22:11.809802	2025-08-03 19:22:11.809816
60	Vannah & Vannah	\N	1	2025-08-03 19:22:13.283001	2025-08-03 19:22:13.283009
61	Winners Circle Injury Law	702-900-7722	1	2025-08-03 19:22:13.725057	2025-08-03 19:22:13.725062
62	Cram Valdez Brigman & Nelson (CVBN)	\N	1	2025-08-03 19:22:24.743559	2025-08-03 19:22:24.743566
63	Felicetti Law Firm	305-998-7000	1	2025-08-03 19:22:25.292087	2025-08-03 19:22:25.292096
64	Hunter Parker	702-544-1789	1	2025-08-03 19:22:25.897253	2025-08-03 19:22:25.89726
65	Ladah Law Firm	\N	1	2025-08-03 19:22:26.429922	2025-08-03 19:22:26.429928
66	Lerner and Rowe	\N	1	2025-08-03 19:22:27.020411	2025-08-03 19:22:27.020417
67	Moss Berg Injury Lawyers	702-222-4555	1	2025-08-03 19:22:27.56565	2025-08-03 19:22:27.565655
68	Moulton Law Firm (Meesha Moulton)	702-602-7500	1	2025-08-03 19:22:28.070667	2025-08-03 19:22:28.070674
69	Rafi Law Firm	623-207-1555	1	2025-08-03 19:22:29.817352	2025-08-03 19:22:29.817358
70	Sang Injury Law Firm	\N	1	2025-08-03 19:22:31.314372	2025-08-03 19:22:31.314377
71	Dimopoulos Injury Law	702-800-6000	1	2025-08-03 19:22:38.654801	2025-08-03 19:22:38.654809
72	JG Law Firm	702-918-4110	1	2025-08-03 19:22:39.607501	2025-08-03 19:22:39.607507
73	West Coast Trial Lawyers	\N	1	2025-08-03 19:22:41.093853	2025-08-03 19:22:41.093858
74	Cloward Trial Lawyers	702-605-5000	1	2025-08-03 19:22:44.454536	2025-08-03 19:22:44.454546
75	J&Y Law Injury and Accident Attorneys	\N	1	2025-08-03 19:22:45.014336	2025-08-03 19:22:45.014343
76	The Cottner Law Firm	702-382-1170	1	2025-08-03 19:22:46.223966	2025-08-03 19:22:46.223973
77	Sprenz Law	\N	1	2025-08-03 19:53:58.599859	2025-08-03 19:53:58.599869
78	Hutchings Law Group	\N	1	2025-08-03 19:53:59.15606	2025-08-03 19:53:59.156066
79	Edward M. Bernstein & Associates	\N	1	2025-08-03 19:53:59.538549	2025-08-03 19:53:59.538555
80	Hicks & Braiser	\N	1	2025-08-03 19:53:59.910951	2025-08-03 19:53:59.910958
81	Heaton & Associates	\N	1	2025-08-03 19:54:00.636656	2025-08-03 19:54:00.636662
82	Kung & Brown	\N	1	2025-08-03 19:54:02.19707	2025-08-03 19:54:02.197089
83	Law Offices OF Meesha Moulton	\N	1	2025-08-03 19:54:02.587205	2025-08-03 19:54:02.587215
84	Sam & Ash Law	\N	1	2025-08-03 19:54:03.080007	2025-08-03 19:54:03.080012
85	Boyack Law Group	\N	1	2025-08-03 19:54:04.053983	2025-08-03 19:54:04.054007
86	Moss & Berg	\N	1	2025-08-03 19:54:06.598939	2025-08-03 19:54:06.598948
87	Tanner Law Firm	\N	1	2025-08-03 19:54:07.123593	2025-08-03 19:54:07.123605
88	Eric Palacios & Associates	\N	1	2025-08-03 19:54:09.406986	2025-08-03 19:54:09.406993
89	KristOf Law Group	\N	1	2025-08-03 19:54:10.53015	2025-08-03 19:54:10.530157
90	Law Office of David Sampson, LLC	\N	1	2025-08-03 19:54:11.124516	2025-08-03 19:54:11.124532
91	Brock Ohlson	\N	1	2025-08-03 19:54:11.993813	2025-08-03 19:54:11.993819
92	David Boehrer Law Firm	\N	1	2025-08-03 19:54:15.620533	2025-08-03 19:54:15.620542
93	Menocal Law Group	\N	1	2025-08-03 19:54:16.347798	2025-08-03 19:54:16.347808
94	Henness & Haight	\N	1	2025-08-03 19:54:19.230833	2025-08-03 19:54:19.23084
95	Law Office of Mauro Fiore Jr.	\N	1	2025-08-03 19:54:19.926668	2025-08-03 19:54:19.926679
96	ER Injury Attorneys	\N	1	2025-08-03 19:54:20.369123	2025-08-03 19:54:20.369132
97	Greenman Goldberg Raby and Martinez	\N	1	2025-08-03 19:54:21.956306	2025-08-03 19:54:21.956312
98	Albright, Stoddard, Warnick, & Albright	\N	1	2025-08-03 19:54:23.849158	2025-08-03 19:54:23.84917
99	Van Law Firm	\N	1	2025-08-03 19:54:26.666422	2025-08-03 19:54:26.666431
100	CEGA Law Group	\N	1	2025-08-03 19:54:27.472899	2025-08-03 19:54:27.472907
101	Clear Counsel Law Group	\N	1	2025-08-03 19:54:28.037366	2025-08-03 19:54:28.037373
102	RICHARD HARRIS LAW FIRM	\N	1	2025-08-03 19:54:31.317841	2025-08-03 19:54:31.317848
103	Gallagher Law	\N	1	2025-08-03 19:54:33.146095	2025-08-03 19:54:33.146104
104	Huang & Associates	\N	1	2025-08-03 19:54:34.018602	2025-08-03 19:54:34.018611
105	Craig P. Kenny	\N	1	2025-08-03 19:54:36.467815	2025-08-03 19:54:36.46782
106	The Advocates Law Group	\N	1	2025-08-03 19:54:45.39842	2025-08-03 19:54:45.398425
107	Nevada Injury Law	\N	1	2025-08-03 19:54:49.4103	2025-08-03 19:54:49.410312
108	Saggese and Associates	\N	1	2025-08-03 19:54:50.866197	2025-08-03 19:54:50.866221
109	Law Offices of Daniel Kim	\N	1	2025-08-03 19:54:55.482351	2025-08-03 19:54:55.48236
110	The 702 Law Firm	\N	1	2025-08-03 19:54:56.145017	2025-08-03 19:54:56.145029
111	YMPK Law Group, Inc	\N	1	2025-08-03 19:54:59.145459	2025-08-03 19:54:59.145468
112	Burk Injury Lawyers	\N	1	2025-08-03 19:55:01.781533	2025-08-03 19:55:01.781542
113	Dang Law Group	\N	1	2025-08-03 19:55:06.018015	2025-08-03 19:55:06.018021
114	G. Dallas Horton	\N	1	2025-08-03 19:55:08.981922	2025-08-03 19:55:08.981929
115	Anthony Paglia Injury Lawyer	\N	1	2025-08-03 19:55:11.696218	2025-08-03 19:55:11.696226
116	The Firm LA, P.C.	\N	1	2025-08-03 19:55:13.744967	2025-08-03 19:55:13.744981
117	Lloyd Baker	\N	1	2025-08-03 19:55:21.24578	2025-08-03 19:55:21.245794
118	Car Accident Lawyer Pros	\N	1	2025-08-03 19:55:24.197551	2025-08-03 19:55:24.197558
119	Drake Legal Group	\N	1	2025-08-03 19:55:26.826357	2025-08-03 19:55:26.826368
120	Hale Injury Law	\N	1	2025-08-03 19:55:29.07057	2025-08-03 19:55:29.070578
121	Heshmati & Associates	\N	1	2025-08-03 19:55:33.06432	2025-08-03 19:55:33.064339
122	Law Office of Eric K. Chen	\N	1	2025-08-03 19:55:33.569505	2025-08-03 19:55:33.569515
123	Willoughby Shulman Injury Lawyers	\N	1	2025-08-03 19:55:34.397886	2025-08-03 19:55:34.397894
124	Pacific West Injury Law	\N	1	2025-08-03 19:55:37.758613	2025-08-03 19:55:37.758657
125	Nwogbe Law Group	\N	1	2025-08-03 19:55:46.232543	2025-08-03 19:55:46.232549
126	The Law Offices of Glen A. Howard Esq., LLC.	\N	1	2025-08-03 19:55:48.031421	2025-08-03 19:55:48.03143
127	Cram Valdez Brigman & Nelson	\N	1	2025-08-03 19:55:52.799707	2025-08-03 19:55:52.799718
128	The Hill Firm	\N	1	2025-08-03 19:55:58.761822	2025-08-03 19:55:58.761836
129	Victory Law	\N	1	2025-08-03 19:56:00.738916	2025-08-03 19:56:00.738926
130	Aaron Law Group	\N	1	2025-08-03 19:56:01.407172	2025-08-03 19:56:01.407181
131	Naqvi Injury Law	\N	1	2025-08-03 19:56:06.446243	2025-08-03 19:56:06.446279
132	Mitchell Rodger's Injury Law	\N	1	2025-08-03 19:56:09.988223	2025-08-03 19:56:09.988231
133	Nobles & Yanez	\N	1	2025-08-03 19:56:10.655086	2025-08-03 19:56:10.655098
134	Jerez Law	\N	1	2025-08-03 19:56:20.795663	2025-08-03 19:56:20.795671
135	Eric Blank	\N	1	2025-08-03 19:56:23.162134	2025-08-03 19:56:23.162154
136	Pomponio Injury Law	\N	1	2025-08-03 19:56:33.904695	2025-08-03 19:56:33.904704
137	Christiansen Trial Lawyers	\N	1	2025-08-03 19:56:35.469156	2025-08-03 19:56:35.469165
138	Christmas Foster Injury Law	\N	1	2025-08-03 19:56:39.643551	2025-08-03 19:56:39.643564
139	Nehme-Tomalka & Associates	\N	1	2025-08-03 19:56:43.424301	2025-08-03 19:56:43.424309
140	Johnson & Gubler PC	\N	1	2025-08-03 19:56:52.34218	2025-08-03 19:56:52.342193
141	Hooks Meng & Clement	\N	1	2025-08-03 19:56:54.631211	2025-08-03 19:56:54.631222
142	SJW Injury Law	\N	1	2025-08-03 19:56:56.384905	2025-08-03 19:56:56.384925
143	Ryan Alexander	\N	1	2025-08-03 19:57:01.800204	2025-08-03 19:57:01.800214
144	Angulo Law Group	\N	1	2025-08-03 19:57:07.045183	2025-08-03 19:57:07.045201
145	Manuel Montelongo Law Offices	\N	1	2025-08-03 19:57:12.136321	2025-08-03 19:57:12.136332
146	Kevin R Hansen Law	\N	1	2025-08-03 19:57:13.432521	2025-08-03 19:57:13.43253
147	Adams, Ren Tavian	\N	1	2025-08-03 19:57:18.62838	2025-08-03 19:57:18.628389
148	Parke Injury Law Firm	\N	1	2025-08-03 19:57:21.18941	2025-08-03 19:57:21.189436
149	FriedMan Injury Law	\N	1	2025-08-03 19:57:30.564436	2025-08-03 19:57:30.564445
150	Griffin Law Group	\N	1	2025-08-03 19:57:32.003567	2025-08-03 19:57:32.003576
151	Brent Carson / Winner & Carson	\N	1	2025-08-03 19:57:45.221637	2025-08-03 19:57:45.22165
152	Gazda & Tadayon Lawyers	\N	1	2025-08-03 19:57:45.970869	2025-08-03 19:57:45.970878
153	Sin City Justicia	\N	1	2025-08-03 19:57:47.123228	2025-08-03 19:57:47.123235
154	O'Reilly Law Group	\N	1	2025-08-03 19:57:51.971247	2025-08-03 19:57:51.971258
155	Alcock & Associates P.C.	\N	1	2025-08-03 19:57:53.716719	2025-08-03 19:57:53.71673
156	Eric H Woods Law Offices	\N	1	2025-08-03 19:58:01.06902	2025-08-03 19:58:01.069035
157	Legal Ride Personal Injury & Criminal Defense Attorneys	\N	1	2025-08-03 19:58:17.060492	2025-08-03 19:58:17.060506
158	Steven Parke	\N	1	2025-08-03 19:58:27.329176	2025-08-03 19:58:27.329189
159	Connell Law	\N	1	2025-08-03 19:58:33.512208	2025-08-03 19:58:33.51222
160	Clark Law Group	\N	1	2025-08-03 19:58:38.415944	2025-08-03 19:58:38.415951
161	Heidari Law Group	\N	1	2025-08-03 19:58:38.846148	2025-08-03 19:58:38.846157
162	Injury Lawyers of Nevada	\N	1	2025-08-03 19:58:39.281258	2025-08-03 19:58:39.281268
163	Donn Prokopius & Beasley	\N	1	2025-08-03 19:58:43.973907	2025-08-03 19:58:43.973981
164	Remmel Law Firm	\N	1	2025-08-03 19:58:46.836025	2025-08-03 19:58:46.836036
165	DR Patti & Associates	\N	1	2025-08-03 19:59:02.662075	2025-08-03 19:59:02.662084
166	LJU Law Firm	\N	1	2025-08-03 19:59:06.428562	2025-08-03 19:59:06.428575
167	Maddox & Cisneros, llp	\N	1	2025-08-03 19:59:06.858477	2025-08-03 19:59:06.858487
168	Loftus Law	\N	1	2025-08-03 19:59:28.345864	2025-08-03 19:59:28.345872
169	Bay Law	\N	1	2025-08-03 19:59:34.576479	2025-08-03 19:59:34.576484
170	Battle Born	\N	1	2025-08-03 19:59:35.706783	2025-08-03 19:59:35.706795
171	Greg D.Jenson	\N	1	2025-08-03 19:59:38.361837	2025-08-03 19:59:38.361857
172	Muaina Injury Law	\N	1	2025-08-03 19:59:39.279066	2025-08-03 19:59:39.279074
173	Temple Injury Law	\N	1	2025-08-03 19:59:45.05596	2025-08-03 19:59:45.055966
174	Trachtman Law	\N	1	2025-08-03 19:59:45.894242	2025-08-03 19:59:45.894251
175	De Vera Law Group	\N	1	2025-08-03 19:59:50.823062	2025-08-03 19:59:50.823081
176	Zhengyi Law Group	\N	1	2025-08-03 19:59:52.514605	2025-08-03 19:59:52.514613
177	Benson Allred	\N	1	2025-08-03 20:00:04.530032	2025-08-03 20:00:04.530039
178	Howard & Howard	\N	1	2025-08-03 20:00:06.248036	2025-08-03 20:00:06.248046
179	Kennedy Kirk T Attorney At Law	\N	1	2025-08-03 20:00:09.91379	2025-08-03 20:00:09.9138
180	Richard M. Lester	\N	1	2025-08-03 20:00:13.992995	2025-08-03 20:00:13.993004
181	Benjamin Durham	\N	1	2025-08-03 20:00:17.2176	2025-08-03 20:00:17.217609
182	The Ruiz Law Firm	\N	1	2025-08-03 20:00:30.271512	2025-08-03 20:00:30.271526
183	Nemerof law	\N	1	2025-08-03 20:00:42.261394	2025-08-03 20:00:42.261404
184	Gina Corena	\N	1	2025-08-03 20:00:43.800617	2025-08-03 20:00:43.800626
185	Gladiator Injury Law	\N	1	2025-08-03 20:00:48.539915	2025-08-03 20:00:48.539925
186	Hawkins	\N	1	2025-08-03 20:00:55.242024	2025-08-03 20:00:55.242045
187	Law Firm of Parke Esquire	\N	1	2025-08-03 20:00:59.378991	2025-08-03 20:00:59.378998
188	Downtown L.A. Law Group	\N	1	2025-08-03 20:01:03.084162	2025-08-03 20:01:03.084167
189	Ameer Shah	\N	1	2025-08-03 20:01:06.031515	2025-08-03 20:01:06.03152
190	McAvoy Amaya & Revero, Attorneys	\N	1	2025-08-03 20:01:06.779312	2025-08-03 20:01:06.779327
191	Alemi Law Group, PC	\N	1	2025-08-03 20:01:21.18982	2025-08-03 20:01:21.189829
192	Calgget	\N	1	2025-08-03 20:01:24.14145	2025-08-03 20:01:24.141458
193	Michael Hua	\N	1	2025-08-03 20:01:25.864423	2025-08-03 20:01:25.864431
194	Paradise	\N	1	2025-08-03 20:01:26.412952	2025-08-03 20:01:26.412959
195	Rivera Law Group	\N	1	2025-08-03 20:01:29.184229	2025-08-03 20:01:29.184235
196	Black Burn	\N	1	2025-08-03 20:01:34.55953	2025-08-03 20:01:34.55954
197	Cox and Wilson PLLC	\N	1	2025-08-03 20:01:39.073753	2025-08-03 20:01:39.07377
198	Law Office of William	\N	1	2025-08-03 20:01:42.893355	2025-08-03 20:01:42.893361
199	Mountain West	\N	1	2025-08-03 20:01:55.762602	2025-08-03 20:01:55.762609
200	Lastein	\N	1	2025-08-03 20:01:57.480481	2025-08-03 20:01:57.480489
201	Massi	\N	1	2025-08-03 20:02:02.206605	2025-08-03 20:02:02.206613
202	GGRM	\N	1	2025-08-03 20:02:43.579897	2025-08-03 20:02:43.579904
203	The Personal Injury	\N	1	2025-08-03 20:02:45.353314	2025-08-03 20:02:45.35332
204	Dufour Law	\N	1	2025-08-03 20:03:05.187925	2025-08-03 20:03:05.187941
205	Brian Boyer	\N	1	2025-08-03 20:03:15.438264	2025-08-03 20:03:15.438273
206	BIGHORN LAW	\N	1	2025-08-03 20:03:36.787427	2025-08-03 20:03:36.787436
207	Richard S. Johnson	\N	1	2025-08-03 20:03:41.643522	2025-08-03 20:03:41.643535
208	The Injury Firm	\N	1	2025-08-03 20:03:48.870169	2025-08-03 20:03:48.870174
209	Aisen, Gill & Associates	\N	1	2025-08-03 20:03:50.708902	2025-08-03 20:03:50.708916
210	The May Firm	\N	1	2025-08-03 20:03:52.509733	2025-08-03 20:03:52.509755
211	Caig P. K	\N	1	2025-08-03 20:03:59.237044	2025-08-03 20:03:59.237054
212	Kch & Bim	\N	1	2025-08-03 20:04:04.01033	2025-08-03 20:04:04.010338
213	MRI law	\N	1	2025-08-03 20:04:04.427382	2025-08-03 20:04:04.427396
214	JK Nelson	\N	1	2025-08-03 20:04:08.742084	2025-08-03 20:04:08.742096
215	Cofer & Geller	\N	1	2025-08-03 20:04:14.559052	2025-08-03 20:04:14.559065
216	Guido Injury Law	\N	1	2025-08-03 20:04:32.943635	2025-08-03 20:04:32.943647
217	Beckstrom Beckstrom	\N	1	2025-08-03 20:04:36.597343	2025-08-03 20:04:36.597351
218	Christiansen Law Offices	\N	1	2025-08-03 20:04:46.096635	2025-08-03 20:04:46.096649
219	Deaver Crafton	\N	1	2025-08-03 20:04:46.652367	2025-08-03 20:04:46.652376
220	The Feldman Firm	\N	1	2025-08-03 20:05:06.277446	2025-08-03 20:05:06.277453
221	POWELL & PISMAN, PLLC	\N	1	2025-08-03 20:05:16.330339	2025-08-03 20:05:16.330347
222	Azizi Law Firm	\N	1	2025-08-03 20:05:23.870609	2025-08-03 20:05:23.870615
223	Burris and Thomas	\N	1	2025-08-03 20:05:24.795637	2025-08-03 20:05:24.795642
224	Cap & Kudler	\N	1	2025-08-03 20:05:25.15794	2025-08-03 20:05:25.15795
225	Law Office of Lawrence Hill	\N	1	2025-08-03 20:05:25.677119	2025-08-03 20:05:25.677131
226	Mueller & Associates	\N	1	2025-08-03 20:05:26.394803	2025-08-03 20:05:26.394817
227	Koch & Brim	\N	1	2025-08-03 20:05:37.37194	2025-08-03 20:05:37.371948
228	Law offices of Jason W. Barrus	\N	1	2025-08-03 20:05:41.215606	2025-08-03 20:05:41.215615
229	Lawrence C. Hill & Associates	\N	1	2025-08-03 20:05:50.35103	2025-08-03 20:05:50.351035
230	Marzola & Ruiz Law Group	\N	1	2025-08-03 20:05:50.808619	2025-08-03 20:05:50.808627
231	Pelata Plank Law Firm	\N	1	2025-08-03 20:05:57.426568	2025-08-03 20:05:57.426579
232	ANKIN LAW OFFICE	\N	1	2025-08-03 20:06:09.851421	2025-08-03 20:06:09.851425
233	Claggett & Sykes Law Firm	\N	1	2025-08-03 20:06:10.501115	2025-08-03 20:06:10.501122
234	Ofelia Markarian	\N	1	2025-08-03 20:06:12.973799	2025-08-03 20:06:12.973806
235	Hwang Law Group	\N	1	2025-08-03 20:06:21.432921	2025-08-03 20:06:21.432929
236	Jack Bernstein Injury Lawyers	\N	1	2025-08-03 20:06:28.847133	2025-08-03 20:06:28.847141
237	LBC Law Group	\N	1	2025-08-03 20:06:33.492416	2025-08-03 20:06:33.492423
238	MAIER GUTIERREZ & ASSOCIATES	\N	1	2025-08-03 20:06:53.3318	2025-08-03 20:06:53.331806
239	Winners Circle	\N	1	2025-08-03 20:06:56.996491	2025-08-03 20:06:56.996499
240	Ralph A. Schwartz, P.C	\N	1	2025-08-03 20:07:15.725476	2025-08-03 20:07:15.725493
241	sang injury law firm	\N	1	2025-08-03 20:07:23.047606	2025-08-03 20:07:23.047612
242	Hinds Injury Law	\N	1	2025-08-03 20:07:25.099207	2025-08-03 20:07:25.099213
243	Peralta Law Group	\N	1	2025-08-03 20:07:38.848304	2025-08-03 20:07:38.848311
244	Cogburn Law Offices	\N	1	2025-08-03 20:07:50.317739	2025-08-03 20:07:50.317748
245	Zaman & Trippiedi PLLC	\N	1	2025-08-03 20:08:03.255277	2025-08-03 20:08:03.255283
246	Brown Injury Law	\N	1	2025-08-03 20:08:08.734294	2025-08-03 20:08:08.7343
247	McReynolds | Vardanyan LLP	\N	1	2025-08-03 20:08:16.900112	2025-08-03 20:08:16.900124
248	RB Injury Lawyers	\N	1	2025-08-03 20:08:17.211526	2025-08-03 20:08:17.211534
249	Lach Injury Law	\N	1	2025-08-03 20:08:25.788693	2025-08-03 20:08:25.788704
250	Kashou Law	\N	1	2025-08-03 20:08:37.761262	2025-08-03 20:08:37.761271
251	Nguyen & Associates	\N	1	2025-08-03 20:08:52.725735	2025-08-03 20:08:52.725749
252	Jason Cook Attorney	\N	1	2025-08-03 20:08:54.427968	2025-08-03 20:08:54.427979
253	Galliher Law / Gallagher Law	\N	1	2025-08-03 20:08:59.056441	2025-08-03 20:08:59.056451
254	BD&J	\N	1	2025-08-03 21:27:59.01139	2025-08-03 21:27:59.011395
255	Krista Devera	\N	1	2025-08-03 21:28:07.895579	2025-08-03 21:28:07.895584
256	Parke Law	\N	1	2025-08-03 21:28:36.686739	2025-08-03 21:28:36.686748
257	Beligan, Beligan, Carnakis LLP.	\N	1	2025-08-03 21:29:41.818082	2025-08-03 21:29:41.81809
258	Heidari Law Group (Set to PRINT)	\N	1	2025-08-03 21:30:23.139804	2025-08-03 21:30:23.139822
259	Arias Sanguinetti Wang and Torrijos LLP	\N	1	2025-08-03 21:30:36.002095	2025-08-03 21:30:36.002112
\.


--
-- TOC entry 4930 (class 0 OID 90762)
-- Dependencies: 219
-- Data for Name: bills; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.bills (id, patient_id, attorney_id, location_id, billed_date, total_billed_charges, status, created_at, updated_at, provider_id) FROM stdin;
1	\N	254	\N	2025-06-09	1729.10	1	2025-08-03 21:27:59.437286	2025-08-03 21:27:59.437286	1
2	\N	254	\N	2025-06-16	1465.14	1	2025-08-03 21:27:59.789331	2025-08-03 21:27:59.789331	1
3	\N	254	\N	2025-06-23	290.32	1	2025-08-03 21:28:00.145445	2025-08-03 21:28:00.145445	1
4	\N	254	\N	2025-06-30	0.00	1	2025-08-03 21:28:00.655633	2025-08-03 21:28:00.655633	2
5	\N	254	\N	2025-06-30	290.32	1	2025-08-03 21:28:01.015121	2025-08-03 21:28:01.015121	1
6	\N	254	\N	2025-06-30	290.32	1	2025-08-03 21:28:01.487166	2025-08-03 21:28:01.487166	3
7	\N	254	\N	2025-07-08	290.32	1	2025-08-03 21:28:02.008873	2025-08-03 21:28:02.008873	4
8	\N	254	\N	2025-07-21	403.92	1	2025-08-03 21:28:02.372258	2025-08-03 21:28:02.372258	1
9	\N	53	\N	2022-10-13	1485.00	1	2025-08-03 21:28:02.829075	2025-08-03 21:28:02.829075	5
10	\N	53	\N	2022-10-14	185.00	1	2025-08-03 21:28:03.18735	2025-08-03 21:28:03.18735	5
11	\N	53	\N	2022-10-19	400.00	1	2025-08-03 21:28:03.597064	2025-08-03 21:28:03.597064	5
12	\N	53	\N	2022-10-21	0.00	1	2025-08-03 21:28:03.90765	2025-08-03 21:28:03.90765	2
13	\N	53	\N	2022-10-21	95.00	1	2025-08-03 21:28:04.430132	2025-08-03 21:28:04.430132	6
14	\N	53	\N	2022-10-27	650.00	1	2025-08-03 21:28:04.948374	2025-08-03 21:28:04.948374	7
15	\N	53	\N	2022-10-28	90.00	1	2025-08-03 21:28:05.322364	2025-08-03 21:28:05.322364	6
16	\N	53	\N	2022-10-28	310.00	1	2025-08-03 21:28:05.651582	2025-08-03 21:28:05.651582	5
17	\N	53	\N	2022-11-11	645.00	1	2025-08-03 21:28:06.001578	2025-08-03 21:28:06.001578	5
18	\N	53	\N	2022-12-12	400.00	1	2025-08-03 21:28:06.439368	2025-08-03 21:28:06.439368	5
19	\N	53	\N	2022-12-12	550.00	1	2025-08-03 21:28:06.779188	2025-08-03 21:28:06.779188	7
20	\N	53	\N	2023-01-19	400.00	1	2025-08-03 21:28:07.061164	2025-08-03 21:28:07.061164	5
21	\N	53	\N	2023-01-19	625.00	1	2025-08-03 21:28:07.410374	2025-08-03 21:28:07.410374	7
22	\N	53	\N	2023-01-30	380.00	1	2025-08-03 21:28:07.727791	2025-08-03 21:28:07.727791	5
23	\N	255	\N	2024-08-06	1595.00	1	2025-08-03 21:28:08.325805	2025-08-03 21:28:08.325805	8
24	\N	255	\N	2024-08-08	265.00	1	2025-08-03 21:28:08.683163	2025-08-03 21:28:08.683163	8
25	\N	255	\N	2024-08-15	346.92	1	2025-08-03 21:28:09.016374	2025-08-03 21:28:09.016374	1
26	\N	255	\N	2024-08-21	281.92	1	2025-08-03 21:28:09.446203	2025-08-03 21:28:09.446203	8
27	\N	255	\N	2024-08-26	604.30	1	2025-08-03 21:28:09.763623	2025-08-03 21:28:09.763623	8
28	\N	255	\N	2024-08-30	302.15	1	2025-08-03 21:28:10.090329	2025-08-03 21:28:10.090329	8
29	\N	255	\N	2024-09-10	0.00	1	2025-08-03 21:28:10.400951	2025-08-03 21:28:10.400951	2
30	\N	255	\N	2024-09-10	223.65	1	2025-08-03 21:28:10.919507	2025-08-03 21:28:10.919507	9
31	\N	255	\N	2024-09-12	375.40	1	2025-08-03 21:28:11.226217	2025-08-03 21:28:11.226217	1
32	\N	255	\N	2024-09-25	302.15	1	2025-08-03 21:28:11.871834	2025-08-03 21:28:11.871834	10
33	\N	255	\N	2024-09-30	280.00	1	2025-08-03 21:28:12.271924	2025-08-03 21:28:12.271924	1
34	\N	255	\N	2024-10-07	680.00	1	2025-08-03 21:28:12.710023	2025-08-03 21:28:12.710023	11
35	\N	255	\N	2024-10-24	280.00	1	2025-08-03 21:28:13.410365	2025-08-03 21:28:13.410365	12
36	\N	255	\N	2024-10-29	280.00	1	2025-08-03 21:28:13.865684	2025-08-03 21:28:13.865684	1
37	\N	255	\N	2024-11-14	280.00	1	2025-08-03 21:28:14.206245	2025-08-03 21:28:14.206245	12
38	\N	255	\N	2024-12-17	113.60	1	2025-08-03 21:28:14.542099	2025-08-03 21:28:14.542099	1
39	\N	49	\N	2025-05-23	1898.75	1	2025-08-03 21:28:14.866864	2025-08-03 21:28:14.866864	1
40	\N	49	\N	2025-05-23	512.47	1	2025-08-03 21:28:15.212356	2025-08-03 21:28:15.212356	12
41	\N	49	\N	2025-05-28	803.02	1	2025-08-03 21:28:15.548314	2025-08-03 21:28:15.548314	1
42	\N	49	\N	2025-05-30	312.47	1	2025-08-03 21:28:15.920462	2025-08-03 21:28:15.920462	1
43	\N	49	\N	2025-06-02	193.97	1	2025-08-03 21:28:16.406753	2025-08-03 21:28:16.406753	13
44	\N	49	\N	2025-06-04	0.00	1	2025-08-03 21:28:16.746411	2025-08-03 21:28:16.746411	2
45	\N	49	\N	2025-06-04	519.57	1	2025-08-03 21:28:17.08233	2025-08-03 21:28:17.08233	1
46	\N	49	\N	2025-06-04	700.00	1	2025-08-03 21:28:17.582705	2025-08-03 21:28:17.582705	14
47	\N	49	\N	2025-06-05	325.62	1	2025-08-03 21:28:17.890324	2025-08-03 21:28:17.890324	1
48	\N	49	\N	2025-06-09	245.07	1	2025-08-03 21:28:18.241649	2025-08-03 21:28:18.241649	6
49	\N	49	\N	2025-06-11	358.67	1	2025-08-03 21:28:18.571503	2025-08-03 21:28:18.571503	1
50	\N	49	\N	2025-06-16	290.32	1	2025-08-03 21:28:18.953685	2025-08-03 21:28:18.953685	1
51	\N	49	\N	2025-06-16	325.62	1	2025-08-03 21:28:19.347016	2025-08-03 21:28:19.347016	13
52	\N	49	\N	2025-06-18	403.92	1	2025-08-03 21:28:19.724828	2025-08-03 21:28:19.724828	12
53	\N	49	\N	2025-06-23	0.00	1	2025-08-03 21:28:20.137921	2025-08-03 21:28:20.137921	2
54	\N	49	\N	2025-06-23	290.32	1	2025-08-03 21:28:20.50033	2025-08-03 21:28:20.50033	1
55	\N	49	\N	2025-06-30	920.89	1	2025-08-03 21:28:20.792744	2025-08-03 21:28:20.792744	1
56	\N	49	\N	2025-07-08	575.00	1	2025-08-03 21:28:21.123266	2025-08-03 21:28:21.123266	14
57	\N	49	\N	2025-07-08	688.10	1	2025-08-03 21:28:21.556495	2025-08-03 21:28:21.556495	4
58	\N	49	\N	2025-07-17	827.92	1	2025-08-03 21:28:21.907916	2025-08-03 21:28:21.907916	1
59	\N	49	\N	2025-07-17	290.32	1	2025-08-03 21:28:22.324721	2025-08-03 21:28:22.324721	4
60	\N	49	\N	2025-07-21	413.57	1	2025-08-03 21:28:22.690837	2025-08-03 21:28:22.690837	3
61	\N	49	\N	2025-07-23	56.35	1	2025-08-03 21:28:23.141326	2025-08-03 21:28:23.141326	4
62	\N	49	\N	2025-07-24	323.57	1	2025-08-03 21:28:23.423947	2025-08-03 21:28:23.423947	1
63	\N	49	\N	2025-07-29	717.52	1	2025-08-03 21:28:23.923622	2025-08-03 21:28:23.923622	15
64	\N	49	\N	2025-07-29	575.00	1	2025-08-03 21:28:24.431279	2025-08-03 21:28:24.431279	16
65	\N	52	\N	2025-04-23	163.50	1	2025-08-03 21:28:24.931966	2025-08-03 21:28:24.931966	17
66	\N	52	\N	2025-04-24	1308.97	1	2025-08-03 21:28:25.408327	2025-08-03 21:28:25.408327	10
67	\N	52	\N	2025-04-25	0.00	1	2025-08-03 21:28:25.785186	2025-08-03 21:28:25.785186	2
68	\N	52	\N	2025-04-30	724.29	1	2025-08-03 21:28:26.234542	2025-08-03 21:28:26.234542	17
69	\N	52	\N	2025-05-04	780.87	1	2025-08-03 21:28:26.706662	2025-08-03 21:28:26.706662	12
70	\N	52	\N	2025-05-09	312.47	1	2025-08-03 21:28:27.086373	2025-08-03 21:28:27.086373	10
71	\N	52	\N	2025-05-09	927.72	1	2025-08-03 21:28:27.551325	2025-08-03 21:28:27.551325	17
72	\N	52	\N	2025-05-09	290.32	1	2025-08-03 21:28:27.958473	2025-08-03 21:28:27.958473	9
73	\N	52	\N	2025-05-23	290.32	1	2025-08-03 21:28:28.467495	2025-08-03 21:28:28.467495	1
74	\N	52	\N	2025-05-23	217.07	1	2025-08-03 21:28:28.862217	2025-08-03 21:28:28.862217	10
75	\N	52	\N	2025-05-23	630.16	1	2025-08-03 21:28:29.255908	2025-08-03 21:28:29.255908	17
76	\N	52	\N	2025-05-28	290.32	1	2025-08-03 21:28:29.745576	2025-08-03 21:28:29.745576	18
77	\N	52	\N	2025-05-29	290.32	1	2025-08-03 21:28:30.093285	2025-08-03 21:28:30.093285	17
78	\N	52	\N	2025-05-30	825.92	1	2025-08-03 21:28:30.433229	2025-08-03 21:28:30.433229	17
79	\N	52	\N	2025-06-03	290.32	1	2025-08-03 21:28:30.848973	2025-08-03 21:28:30.848973	9
80	\N	52	\N	2025-06-05	290.32	1	2025-08-03 21:28:31.187845	2025-08-03 21:28:31.187845	12
81	\N	52	\N	2025-06-11	314.52	1	2025-08-03 21:28:31.522732	2025-08-03 21:28:31.522732	9
82	\N	52	\N	2025-06-16	290.32	1	2025-08-03 21:28:31.848783	2025-08-03 21:28:31.848783	17
83	\N	52	\N	2025-06-17	314.52	1	2025-08-03 21:28:32.19364	2025-08-03 21:28:32.19364	17
84	\N	52	\N	2025-06-30	290.32	1	2025-08-03 21:28:32.535978	2025-08-03 21:28:32.535978	18
85	\N	52	\N	2025-06-30	325.62	1	2025-08-03 21:28:32.848081	2025-08-03 21:28:32.848081	17
86	\N	52	\N	2025-07-08	325.62	1	2025-08-03 21:28:33.174071	2025-08-03 21:28:33.174071	17
87	\N	52	\N	2025-07-08	312.47	1	2025-08-03 21:28:33.492492	2025-08-03 21:28:33.492492	9
88	\N	52	\N	2025-07-08	80.55	1	2025-08-03 21:28:33.854415	2025-08-03 21:28:33.854415	12
89	\N	52	\N	2025-07-17	377.47	1	2025-08-03 21:28:34.226418	2025-08-03 21:28:34.226418	10
90	\N	52	\N	2025-07-17	312.47	1	2025-08-03 21:28:34.577073	2025-08-03 21:28:34.577073	17
91	\N	52	\N	2025-07-21	505.57	1	2025-08-03 21:28:34.913152	2025-08-03 21:28:34.913152	17
92	\N	52	\N	2025-07-23	290.32	1	2025-08-03 21:28:35.317036	2025-08-03 21:28:35.317036	17
93	\N	52	\N	2025-07-24	615.32	1	2025-08-03 21:28:35.909752	2025-08-03 21:28:35.909752	3
94	\N	52	\N	2025-07-30	290.32	1	2025-08-03 21:28:36.479512	2025-08-03 21:28:36.479512	17
95	\N	256	\N	2025-04-25	733.75	1	2025-08-03 21:28:37.100002	2025-08-03 21:28:37.100002	18
96	\N	256	\N	2025-04-30	2877.13	1	2025-08-03 21:28:37.576551	2025-08-03 21:28:37.576551	18
97	\N	256	\N	2025-05-09	290.32	1	2025-08-03 21:28:38.135943	2025-08-03 21:28:38.135943	18
98	\N	256	\N	2025-05-15	512.47	1	2025-08-03 21:28:38.75026	2025-08-03 21:28:38.75026	18
99	\N	256	\N	2025-05-22	297.62	1	2025-08-03 21:28:39.274762	2025-08-03 21:28:39.274762	18
100	\N	256	\N	2025-05-30	290.32	1	2025-08-03 21:28:39.841558	2025-08-03 21:28:39.841558	18
101	\N	256	\N	2025-06-10	290.32	1	2025-08-03 21:28:40.508529	2025-08-03 21:28:40.508529	9
102	\N	256	\N	2025-06-11	290.32	1	2025-08-03 21:28:41.247355	2025-08-03 21:28:41.247355	15
103	\N	256	\N	2025-06-16	290.32	1	2025-08-03 21:28:42.000375	2025-08-03 21:28:42.000375	15
104	\N	256	\N	2025-06-23	0.00	1	2025-08-03 21:28:42.535648	2025-08-03 21:28:42.535648	2
105	\N	256	\N	2025-06-23	290.32	1	2025-08-03 21:28:43.201552	2025-08-03 21:28:43.201552	12
106	\N	256	\N	2025-06-30	700.00	1	2025-08-03 21:28:43.777574	2025-08-03 21:28:43.777574	11
107	\N	256	\N	2025-06-30	290.32	1	2025-08-03 21:28:44.358949	2025-08-03 21:28:44.358949	15
108	\N	256	\N	2025-06-30	290.32	1	2025-08-03 21:28:44.842961	2025-08-03 21:28:44.842961	3
109	\N	256	\N	2025-06-30	290.32	1	2025-08-03 21:28:45.330739	2025-08-03 21:28:45.330739	9
110	\N	256	\N	2025-07-08	615.00	1	2025-08-03 21:28:45.793391	2025-08-03 21:28:45.793391	11
111	\N	256	\N	2025-07-08	290.32	1	2025-08-03 21:28:46.29759	2025-08-03 21:28:46.29759	15
112	\N	256	\N	2025-07-08	290.32	1	2025-08-03 21:28:46.884365	2025-08-03 21:28:46.884365	9
113	\N	256	\N	2025-07-17	290.32	1	2025-08-03 21:28:47.483024	2025-08-03 21:28:47.483024	18
114	\N	256	\N	2025-07-17	290.32	1	2025-08-03 21:28:48.030432	2025-08-03 21:28:48.030432	9
115	\N	256	\N	2025-07-21	0.00	1	2025-08-03 21:28:48.441144	2025-08-03 21:28:48.441144	2
116	\N	256	\N	2025-07-23	290.32	1	2025-08-03 21:28:49.099839	2025-08-03 21:28:49.099839	15
117	\N	256	\N	2025-07-29	700.00	1	2025-08-03 21:28:49.567583	2025-08-03 21:28:49.567583	14
118	\N	256	\N	2025-07-29	290.32	1	2025-08-03 21:28:50.10914	2025-08-03 21:28:50.10914	3
119	\N	44	\N	2025-07-29	484.27	1	2025-08-03 21:28:50.77777	2025-08-03 21:28:50.77777	18
120	\N	44	\N	2025-07-29	2491.42	1	2025-08-03 21:28:51.421626	2025-08-03 21:28:51.421626	15
121	\N	53	\N	2025-01-02	1902.40	1	2025-08-03 21:28:51.87206	2025-08-03 21:28:51.87206	6
122	\N	52	\N	2025-07-21	1548.75	1	2025-08-03 21:28:52.394981	2025-08-03 21:28:52.394981	6
123	\N	52	\N	2025-07-23	1329.05	1	2025-08-03 21:28:52.890704	2025-08-03 21:28:52.890704	6
124	\N	52	\N	2025-07-29	0.00	1	2025-08-03 21:28:53.528839	2025-08-03 21:28:53.528839	2
125	\N	52	\N	2025-07-29	638.50	1	2025-08-03 21:28:53.935977	2025-08-03 21:28:53.935977	6
126	\N	44	\N	2025-05-09	2092.72	1	2025-08-03 21:28:54.450369	2025-08-03 21:28:54.450369	10
127	\N	44	\N	2025-05-15	659.14	1	2025-08-03 21:28:54.907474	2025-08-03 21:28:54.907474	6
128	\N	44	\N	2025-05-23	700.00	1	2025-08-03 21:28:55.667501	2025-08-03 21:28:55.667501	11
129	\N	44	\N	2025-05-23	1266.32	1	2025-08-03 21:28:56.289858	2025-08-03 21:28:56.289858	6
130	\N	44	\N	2025-06-03	208.50	1	2025-08-03 21:28:56.853592	2025-08-03 21:28:56.853592	6
131	\N	44	\N	2025-06-04	615.00	1	2025-08-03 21:28:57.377976	2025-08-03 21:28:57.377976	11
132	\N	44	\N	2025-06-04	368.82	1	2025-08-03 21:28:57.901423	2025-08-03 21:28:57.901423	6
133	\N	44	\N	2025-06-05	290.32	1	2025-08-03 21:28:58.52368	2025-08-03 21:28:58.52368	6
134	\N	44	\N	2025-06-10	368.82	1	2025-08-03 21:28:59.577224	2025-08-03 21:28:59.577224	6
135	\N	44	\N	2025-06-16	780.87	1	2025-08-03 21:29:00.231903	2025-08-03 21:29:00.231903	6
136	\N	44	\N	2025-06-18	490.32	1	2025-08-03 21:29:00.807783	2025-08-03 21:29:00.807783	6
137	\N	44	\N	2025-06-19	174.85	1	2025-08-03 21:29:01.372922	2025-08-03 21:29:01.372922	3
138	\N	44	\N	2025-06-30	1097.72	1	2025-08-03 21:29:02.041747	2025-08-03 21:29:02.041747	6
139	\N	44	\N	2025-07-17	280.00	1	2025-08-03 21:29:02.661531	2025-08-03 21:29:02.661531	4
140	\N	44	\N	2025-07-21	290.32	1	2025-08-03 21:29:03.30571	2025-08-03 21:29:03.30571	6
141	\N	44	\N	2025-07-23	358.50	1	2025-08-03 21:29:03.856569	2025-08-03 21:29:03.856569	6
142	\N	44	\N	2025-07-29	0.00	1	2025-08-03 21:29:04.370345	2025-08-03 21:29:04.370345	2
143	\N	47	\N	2025-02-17	1029.22	1	2025-08-03 21:29:04.816776	2025-08-03 21:29:04.816776	10
144	\N	47	\N	2025-02-24	1387.47	1	2025-08-03 21:29:05.700401	2025-08-03 21:29:05.700401	13
145	\N	47	\N	2025-03-06	312.47	1	2025-08-03 21:29:06.212521	2025-08-03 21:29:06.212521	13
146	\N	47	\N	2025-03-10	490.32	1	2025-08-03 21:29:06.87056	2025-08-03 21:29:06.87056	13
147	\N	47	\N	2025-03-13	753.02	1	2025-08-03 21:29:07.394488	2025-08-03 21:29:07.394488	13
148	\N	61	\N	2025-04-18	700.00	1	2025-08-03 21:29:07.89921	2025-08-03 21:29:07.89921	14
149	\N	44	\N	2025-01-02	849.22	1	2025-08-03 21:29:08.570325	2025-08-03 21:29:08.570325	10
150	\N	44	\N	2025-01-02	703.14	1	2025-08-03 21:29:09.01096	2025-08-03 21:29:09.01096	12
151	\N	44	\N	2025-01-13	1305.94	1	2025-08-03 21:29:09.753938	2025-08-03 21:29:09.753938	19
152	\N	44	\N	2025-01-13	700.00	1	2025-08-03 21:29:10.46576	2025-08-03 21:29:10.46576	20
153	\N	44	\N	2025-01-13	306.14	1	2025-08-03 21:29:11.28354	2025-08-03 21:29:11.28354	21
154	\N	44	\N	2025-01-14	323.97	1	2025-08-03 21:29:11.843477	2025-08-03 21:29:11.843477	21
155	\N	44	\N	2025-01-20	514.24	1	2025-08-03 21:29:12.293936	2025-08-03 21:29:12.293936	19
156	\N	44	\N	2025-01-22	595.27	1	2025-08-03 21:29:12.735874	2025-08-03 21:29:12.735874	19
157	\N	44	\N	2025-01-22	320.27	1	2025-08-03 21:29:13.21778	2025-08-03 21:29:13.21778	21
158	\N	44	\N	2025-01-29	320.27	1	2025-08-03 21:29:13.728658	2025-08-03 21:29:13.728658	21
159	\N	44	\N	2025-02-02	563.47	1	2025-08-03 21:29:14.135632	2025-08-03 21:29:14.135632	19
160	\N	44	\N	2025-02-10	714.64	1	2025-08-03 21:29:14.637008	2025-08-03 21:29:14.637008	19
161	\N	44	\N	2025-02-12	320.27	1	2025-08-03 21:29:15.281666	2025-08-03 21:29:15.281666	19
162	\N	44	\N	2025-02-17	680.00	1	2025-08-03 21:29:16.036621	2025-08-03 21:29:16.036621	11
163	\N	44	\N	2025-02-17	297.62	1	2025-08-03 21:29:16.49379	2025-08-03 21:29:16.49379	9
164	\N	44	\N	2025-02-19	342.62	1	2025-08-03 21:29:16.989075	2025-08-03 21:29:16.989075	19
165	\N	44	\N	2025-02-24	309.17	1	2025-08-03 21:29:17.440169	2025-08-03 21:29:17.440169	19
166	\N	44	\N	2025-02-27	297.62	1	2025-08-03 21:29:17.975922	2025-08-03 21:29:17.975922	9
167	\N	44	\N	2025-02-28	297.62	1	2025-08-03 21:29:18.454697	2025-08-03 21:29:18.454697	18
168	\N	44	\N	2025-03-06	752.67	1	2025-08-03 21:29:19.004641	2025-08-03 21:29:19.004641	9
169	\N	70	\N	2025-02-19	2106.37	1	2025-08-03 21:29:19.467212	2025-08-03 21:29:19.467212	18
170	\N	70	\N	2025-02-24	514.52	1	2025-08-03 21:29:19.887861	2025-08-03 21:29:19.887861	9
171	\N	70	\N	2025-02-26	233.97	1	2025-08-03 21:29:20.365242	2025-08-03 21:29:20.365242	18
172	\N	70	\N	2025-03-13	0.00	1	2025-08-03 21:29:20.782459	2025-08-03 21:29:20.782459	2
173	\N	70	\N	2025-03-28	290.32	1	2025-08-03 21:29:21.64048	2025-08-03 21:29:21.64048	9
174	\N	70	\N	2025-04-04	0.00	1	2025-08-03 21:29:22.079292	2025-08-03 21:29:22.079292	2
175	\N	70	\N	2025-04-04	290.32	1	2025-08-03 21:29:22.556138	2025-08-03 21:29:22.556138	9
176	\N	70	\N	2025-06-09	700.00	1	2025-08-03 21:29:22.976451	2025-08-03 21:29:22.976451	14
177	\N	70	\N	2025-07-08	1000.00	1	2025-08-03 21:29:23.52028	2025-08-03 21:29:23.52028	14
178	\N	131	\N	2024-12-17	730.87	1	2025-08-03 21:29:24.219521	2025-08-03 21:29:24.219521	22
179	\N	131	\N	2024-12-17	290.32	1	2025-08-03 21:29:24.769136	2025-08-03 21:29:24.769136	13
180	\N	131	\N	2024-12-17	1087.06	1	2025-08-03 21:29:25.330749	2025-08-03 21:29:25.330749	10
181	\N	131	\N	2025-01-02	0.00	1	2025-08-03 21:29:25.753637	2025-08-03 21:29:25.753637	2
182	\N	131	\N	2025-01-02	3911.27	1	2025-08-03 21:29:26.166029	2025-08-03 21:29:26.166029	13
183	\N	131	\N	2025-01-02	312.47	1	2025-08-03 21:29:26.675332	2025-08-03 21:29:26.675332	21
184	\N	131	\N	2025-01-13	853.09	1	2025-08-03 21:29:27.345616	2025-08-03 21:29:27.345616	13
185	\N	131	\N	2025-01-13	490.32	1	2025-08-03 21:29:27.932179	2025-08-03 21:29:27.932179	10
186	\N	131	\N	2025-01-20	290.32	1	2025-08-03 21:29:28.503586	2025-08-03 21:29:28.503586	13
187	\N	131	\N	2025-01-20	174.85	1	2025-08-03 21:29:29.103883	2025-08-03 21:29:29.103883	10
188	\N	131	\N	2025-01-22	297.62	1	2025-08-03 21:29:29.493956	2025-08-03 21:29:29.493956	13
189	\N	131	\N	2025-01-22	290.32	1	2025-08-03 21:29:29.989121	2025-08-03 21:29:29.989121	10
190	\N	131	\N	2025-01-29	290.32	1	2025-08-03 21:29:30.390467	2025-08-03 21:29:30.390467	13
191	\N	131	\N	2025-02-02	275.00	1	2025-08-03 21:29:30.856869	2025-08-03 21:29:30.856869	10
192	\N	44	\N	2025-04-04	1780.50	1	2025-08-03 21:29:31.320743	2025-08-03 21:29:31.320743	9
193	\N	57	\N	2024-03-25	550.00	1	2025-08-03 21:29:31.905715	2025-08-03 21:29:31.905715	6
194	\N	57	\N	2024-03-27	365.00	1	2025-08-03 21:29:32.408727	2025-08-03 21:29:32.408727	6
195	\N	57	\N	2024-03-29	160.00	1	2025-08-03 21:29:33.00798	2025-08-03 21:29:33.00798	6
196	\N	57	\N	2024-04-03	650.00	1	2025-08-03 21:29:33.531988	2025-08-03 21:29:33.531988	11
197	\N	57	\N	2024-04-03	665.00	1	2025-08-03 21:29:34.006615	2025-08-03 21:29:34.006615	6
198	\N	57	\N	2024-04-05	115.00	1	2025-08-03 21:29:34.337004	2025-08-03 21:29:34.337004	9
199	\N	57	\N	2024-04-09	265.00	1	2025-08-03 21:29:34.760688	2025-08-03 21:29:34.760688	6
200	\N	57	\N	2024-04-11	160.00	1	2025-08-03 21:29:35.203039	2025-08-03 21:29:35.203039	6
201	\N	57	\N	2024-04-16	0.00	1	2025-08-03 21:29:35.649447	2025-08-03 21:29:35.649447	2
202	\N	57	\N	2024-04-16	385.00	1	2025-08-03 21:29:36.032168	2025-08-03 21:29:36.032168	6
203	\N	57	\N	2024-04-17	225.00	1	2025-08-03 21:29:36.460811	2025-08-03 21:29:36.460811	6
204	\N	57	\N	2024-04-23	210.00	1	2025-08-03 21:29:36.883019	2025-08-03 21:29:36.883019	6
205	\N	57	\N	2024-04-29	550.00	1	2025-08-03 21:29:37.260245	2025-08-03 21:29:37.260245	11
206	\N	57	\N	2024-04-29	225.00	1	2025-08-03 21:29:37.699165	2025-08-03 21:29:37.699165	6
207	\N	57	\N	2024-04-30	225.00	1	2025-08-03 21:29:38.168797	2025-08-03 21:29:38.168797	6
208	\N	57	\N	2024-05-07	160.00	1	2025-08-03 21:29:38.562579	2025-08-03 21:29:38.562579	6
209	\N	57	\N	2024-05-15	625.00	1	2025-08-03 21:29:39.03442	2025-08-03 21:29:39.03442	11
210	\N	57	\N	2024-05-15	225.00	1	2025-08-03 21:29:39.513537	2025-08-03 21:29:39.513537	6
211	\N	57	\N	2024-05-21	160.00	1	2025-08-03 21:29:39.960813	2025-08-03 21:29:39.960813	6
212	\N	57	\N	2024-05-29	160.00	1	2025-08-03 21:29:40.423428	2025-08-03 21:29:40.423428	6
213	\N	57	\N	2024-06-05	215.00	1	2025-08-03 21:29:40.978725	2025-08-03 21:29:40.978725	6
214	\N	57	\N	2024-06-10	450.00	1	2025-08-03 21:29:41.477736	2025-08-03 21:29:41.477736	6
215	\N	257	\N	2025-06-03	1774.10	1	2025-08-03 21:29:42.228264	2025-08-03 21:29:42.228264	12
216	\N	257	\N	2025-06-04	491.57	1	2025-08-03 21:29:42.654659	2025-08-03 21:29:42.654659	1
217	\N	257	\N	2025-06-09	491.57	1	2025-08-03 21:29:43.098844	2025-08-03 21:29:43.098844	1
218	\N	257	\N	2025-06-10	491.57	1	2025-08-03 21:29:43.731614	2025-08-03 21:29:43.731614	12
219	\N	257	\N	2025-06-11	295.57	1	2025-08-03 21:29:44.255339	2025-08-03 21:29:44.255339	1
220	\N	257	\N	2025-06-16	295.57	1	2025-08-03 21:29:44.782023	2025-08-03 21:29:44.782023	1
221	\N	257	\N	2025-06-16	293.70	1	2025-08-03 21:29:45.243785	2025-08-03 21:29:45.243785	10
222	\N	257	\N	2025-06-19	411.02	1	2025-08-03 21:29:45.703355	2025-08-03 21:29:45.703355	1
223	\N	257	\N	2025-06-23	411.02	1	2025-08-03 21:29:46.177036	2025-08-03 21:29:46.177036	1
224	\N	257	\N	2025-06-23	484.27	1	2025-08-03 21:29:46.667388	2025-08-03 21:29:46.667388	12
225	\N	257	\N	2025-06-30	1160.56	1	2025-08-03 21:29:47.121968	2025-08-03 21:29:47.121968	1
226	\N	257	\N	2025-07-08	595.24	1	2025-08-03 21:29:47.752079	2025-08-03 21:29:47.752079	4
227	\N	257	\N	2025-07-17	708.84	1	2025-08-03 21:29:48.101692	2025-08-03 21:29:48.101692	1
228	\N	257	\N	2025-07-17	700.00	1	2025-08-03 21:29:48.869295	2025-08-03 21:29:48.869295	14
229	\N	257	\N	2025-07-17	297.62	1	2025-08-03 21:29:49.366315	2025-08-03 21:29:49.366315	4
230	\N	257	\N	2025-07-17	297.62	1	2025-08-03 21:29:50.002325	2025-08-03 21:29:50.002325	3
231	\N	257	\N	2025-07-21	297.62	1	2025-08-03 21:29:50.53275	2025-08-03 21:29:50.53275	1
232	\N	257	\N	2025-07-23	297.62	1	2025-08-03 21:29:51.22674	2025-08-03 21:29:51.22674	4
233	\N	257	\N	2025-07-24	297.62	1	2025-08-03 21:29:51.756022	2025-08-03 21:29:51.756022	1
234	\N	257	\N	2025-07-29	0.00	1	2025-08-03 21:29:52.243236	2025-08-03 21:29:52.243236	2
235	\N	257	\N	2025-07-29	297.62	1	2025-08-03 21:29:52.754681	2025-08-03 21:29:52.754681	1
236	\N	257	\N	2025-07-29	740.00	1	2025-08-03 21:29:53.212637	2025-08-03 21:29:53.212637	14
237	\N	257	\N	2025-07-29	465.50	1	2025-08-03 21:29:53.636291	2025-08-03 21:29:53.636291	4
238	\N	205	\N	2025-04-04	3105.24	1	2025-08-03 21:29:54.108693	2025-08-03 21:29:54.108693	19
239	\N	205	\N	2025-04-10	644.24	1	2025-08-03 21:29:54.507993	2025-08-03 21:29:54.507993	19
240	\N	205	\N	2025-04-14	320.27	1	2025-08-03 21:29:54.934674	2025-08-03 21:29:54.934674	19
241	\N	205	\N	2025-04-18	1146.96	1	2025-08-03 21:29:55.354787	2025-08-03 21:29:55.354787	19
242	\N	205	\N	2025-04-23	290.32	1	2025-08-03 21:29:55.80482	2025-08-03 21:29:55.80482	19
243	\N	205	\N	2025-04-24	323.97	1	2025-08-03 21:29:56.218381	2025-08-03 21:29:56.218381	18
244	\N	205	\N	2025-04-25	595.27	1	2025-08-03 21:29:56.647505	2025-08-03 21:29:56.647505	19
245	\N	205	\N	2025-04-30	325.62	1	2025-08-03 21:29:57.10119	2025-08-03 21:29:57.10119	19
246	\N	205	\N	2025-05-04	792.52	1	2025-08-03 21:29:57.529213	2025-08-03 21:29:57.529213	19
247	\N	205	\N	2025-05-09	807.84	1	2025-08-03 21:29:58.115044	2025-08-03 21:29:58.115044	19
248	\N	205	\N	2025-05-15	325.62	1	2025-08-03 21:29:58.565194	2025-08-03 21:29:58.565194	19
249	\N	205	\N	2025-05-23	323.97	1	2025-08-03 21:29:59.153988	2025-08-03 21:29:59.153988	19
250	\N	205	\N	2025-05-28	859.17	1	2025-08-03 21:29:59.524307	2025-08-03 21:29:59.524307	19
251	\N	205	\N	2025-05-28	841.09	1	2025-08-03 21:29:59.959387	2025-08-03 21:29:59.959387	10
252	\N	205	\N	2025-05-30	484.27	1	2025-08-03 21:30:00.44833	2025-08-03 21:30:00.44833	10
253	\N	205	\N	2025-06-04	323.97	1	2025-08-03 21:30:00.916777	2025-08-03 21:30:00.916777	19
254	\N	205	\N	2025-06-09	323.57	1	2025-08-03 21:30:01.336563	2025-08-03 21:30:01.336563	19
255	\N	205	\N	2025-06-11	442.40	1	2025-08-03 21:30:01.693656	2025-08-03 21:30:01.693656	19
256	\N	205	\N	2025-06-16	312.47	1	2025-08-03 21:30:02.143904	2025-08-03 21:30:02.143904	19
257	\N	205	\N	2025-06-18	253.35	1	2025-08-03 21:30:02.548789	2025-08-03 21:30:02.548789	19
258	\N	205	\N	2025-06-23	323.57	1	2025-08-03 21:30:03.081935	2025-08-03 21:30:03.081935	19
259	\N	205	\N	2025-06-30	517.52	1	2025-08-03 21:30:03.625614	2025-08-03 21:30:03.625614	19
260	\N	205	\N	2025-07-08	534.22	1	2025-08-03 21:30:04.035801	2025-08-03 21:30:04.035801	19
261	\N	44	\N	2025-06-02	1808.75	1	2025-08-03 21:30:04.370031	2025-08-03 21:30:04.370031	12
262	\N	44	\N	2025-06-03	497.62	1	2025-08-03 21:30:04.815571	2025-08-03 21:30:04.815571	9
263	\N	44	\N	2025-06-04	705.62	1	2025-08-03 21:30:05.325946	2025-08-03 21:30:05.325946	18
264	\N	44	\N	2025-06-09	297.62	1	2025-08-03 21:30:05.933989	2025-08-03 21:30:05.933989	9
265	\N	44	\N	2025-06-09	290.32	1	2025-08-03 21:30:06.477379	2025-08-03 21:30:06.477379	12
266	\N	44	\N	2025-06-11	0.00	1	2025-08-03 21:30:07.23883	2025-08-03 21:30:07.23883	2
267	\N	44	\N	2025-06-11	700.00	1	2025-08-03 21:30:07.682137	2025-08-03 21:30:07.682137	11
268	\N	44	\N	2025-06-11	290.32	1	2025-08-03 21:30:08.276793	2025-08-03 21:30:08.276793	15
269	\N	44	\N	2025-06-16	290.32	1	2025-08-03 21:30:08.764344	2025-08-03 21:30:08.764344	18
270	\N	44	\N	2025-06-16	290.32	1	2025-08-03 21:30:09.213475	2025-08-03 21:30:09.213475	10
271	\N	44	\N	2025-06-18	312.47	1	2025-08-03 21:30:09.736844	2025-08-03 21:30:09.736844	15
272	\N	44	\N	2025-06-23	290.32	1	2025-08-03 21:30:10.386466	2025-08-03 21:30:10.386466	15
273	\N	44	\N	2025-06-30	615.00	1	2025-08-03 21:30:10.969935	2025-08-03 21:30:10.969935	11
274	\N	44	\N	2025-06-30	580.64	1	2025-08-03 21:30:11.80279	2025-08-03 21:30:11.80279	15
275	\N	44	\N	2025-07-01	290.32	1	2025-08-03 21:30:12.316307	2025-08-03 21:30:12.316307	3
276	\N	44	\N	2025-07-08	580.64	1	2025-08-03 21:30:12.671681	2025-08-03 21:30:12.671681	9
277	\N	44	\N	2025-07-17	870.96	1	2025-08-03 21:30:13.192149	2025-08-03 21:30:13.192149	15
278	\N	44	\N	2025-07-21	0.00	1	2025-08-03 21:30:13.829515	2025-08-03 21:30:13.829515	2
279	\N	44	\N	2025-07-21	290.32	1	2025-08-03 21:30:14.468431	2025-08-03 21:30:14.468431	18
280	\N	44	\N	2025-07-23	312.47	1	2025-08-03 21:30:15.072926	2025-08-03 21:30:15.072926	9
281	\N	44	\N	2025-07-24	290.32	1	2025-08-03 21:30:15.592131	2025-08-03 21:30:15.592131	15
282	\N	44	\N	2025-06-30	700.00	1	2025-08-03 21:30:16.401918	2025-08-03 21:30:16.401918	14
283	\N	44	\N	2025-06-30	1715.89	1	2025-08-03 21:30:17.193223	2025-08-03 21:30:17.193223	17
284	\N	44	\N	2025-07-08	467.94	1	2025-08-03 21:30:17.678169	2025-08-03 21:30:17.678169	17
285	\N	44	\N	2025-07-17	217.07	1	2025-08-03 21:30:18.057601	2025-08-03 21:30:18.057601	17
286	\N	44	\N	2025-07-17	233.97	1	2025-08-03 21:30:18.594726	2025-08-03 21:30:18.594726	3
287	\N	44	\N	2025-07-23	233.97	1	2025-08-03 21:30:19.336919	2025-08-03 21:30:19.336919	23
288	\N	44	\N	2025-07-24	233.97	1	2025-08-03 21:30:19.839307	2025-08-03 21:30:19.839307	3
289	\N	44	\N	2025-07-29	588.88	1	2025-08-03 21:30:20.504357	2025-08-03 21:30:20.504357	17
290	\N	44	\N	2025-07-30	90.00	1	2025-08-03 21:30:21.064981	2025-08-03 21:30:21.064981	17
291	\N	57	\N	2022-11-09	920.00	1	2025-08-03 21:30:22.187307	2025-08-03 21:30:22.187307	24
292	\N	57	\N	2022-11-11	95.00	1	2025-08-03 21:30:22.825876	2025-08-03 21:30:22.825876	24
293	\N	258	\N	2025-02-28	1120.45	1	2025-08-03 21:30:23.81984	2025-08-03 21:30:23.81984	20
294	66	57	\N	2025-01-02	1995.40	1	2025-08-03 21:30:24.44595	2025-08-03 21:30:24.44595	6
295	66	57	\N	2025-01-13	1206.76	1	2025-08-03 21:30:24.924545	2025-08-03 21:30:24.924545	6
296	66	57	\N	2025-01-13	290.32	1	2025-08-03 21:30:25.439989	2025-08-03 21:30:25.439989	21
297	66	57	\N	2025-01-14	764.12	1	2025-08-03 21:30:25.999486	2025-08-03 21:30:25.999486	6
298	66	57	\N	2025-01-20	539.22	1	2025-08-03 21:30:26.529445	2025-08-03 21:30:26.529445	6
299	66	57	\N	2025-01-22	680.00	1	2025-08-03 21:30:27.112792	2025-08-03 21:30:27.112792	11
300	66	57	\N	2025-01-27	738.04	1	2025-08-03 21:30:27.616256	2025-08-03 21:30:27.616256	6
301	66	57	\N	2025-02-02	315.47	1	2025-08-03 21:30:28.415608	2025-08-03 21:30:28.415608	6
302	66	57	\N	2025-02-10	0.00	1	2025-08-03 21:30:28.961273	2025-08-03 21:30:28.961273	2
303	66	57	\N	2025-02-10	575.00	1	2025-08-03 21:30:29.455504	2025-08-03 21:30:29.455504	11
304	66	57	\N	2025-02-10	290.32	1	2025-08-03 21:30:29.893412	2025-08-03 21:30:29.893412	10
305	66	57	\N	2025-02-10	692.79	1	2025-08-03 21:30:30.337747	2025-08-03 21:30:30.337747	6
306	66	57	\N	2025-02-17	761.54	1	2025-08-03 21:30:30.818396	2025-08-03 21:30:30.818396	6
307	66	57	\N	2025-02-19	648.00	1	2025-08-03 21:30:31.43921	2025-08-03 21:30:31.43921	11
308	66	57	\N	2025-02-26	402.47	1	2025-08-03 21:30:31.893661	2025-08-03 21:30:31.893661	6
309	66	57	\N	2025-03-06	815.32	1	2025-08-03 21:30:32.444191	2025-08-03 21:30:32.444191	6
310	66	57	\N	2025-03-13	323.97	1	2025-08-03 21:30:33.068271	2025-08-03 21:30:33.068271	6
311	66	57	\N	2025-03-26	368.82	1	2025-08-03 21:30:33.661421	2025-08-03 21:30:33.661421	6
312	66	57	\N	2025-03-31	368.82	1	2025-08-03 21:30:34.181917	2025-08-03 21:30:34.181917	6
313	66	57	\N	2025-04-14	323.97	1	2025-08-03 21:30:34.727791	2025-08-03 21:30:34.727791	6
314	66	57	\N	2025-04-18	323.97	1	2025-08-03 21:30:35.277242	2025-08-03 21:30:35.277242	6
315	66	57	\N	2025-04-24	275.00	1	2025-08-03 21:30:35.810102	2025-08-03 21:30:35.810102	6
316	\N	259	\N	2025-02-17	315.47	1	2025-08-03 21:30:36.423784	2025-08-03 21:30:36.423784	18
317	\N	259	\N	2025-02-17	1808.75	1	2025-08-03 21:30:36.979401	2025-08-03 21:30:36.979401	9
318	\N	259	\N	2025-02-24	680.00	1	2025-08-03 21:30:37.326208	2025-08-03 21:30:37.326208	11
319	\N	259	\N	2025-02-26	314.52	1	2025-08-03 21:30:37.863435	2025-08-03 21:30:37.863435	9
320	\N	259	\N	2025-03-06	575.00	1	2025-08-03 21:30:38.326935	2025-08-03 21:30:38.326935	11
321	\N	259	\N	2025-03-24	615.00	1	2025-08-03 21:30:38.791141	2025-08-03 21:30:38.791141	11
322	\N	259	\N	2025-03-28	680.00	1	2025-08-03 21:30:39.478095	2025-08-03 21:30:39.478095	11
323	\N	259	\N	2025-07-23	700.00	1	2025-08-03 21:30:39.870844	2025-08-03 21:30:39.870844	14
324	\N	101	\N	2025-06-04	778.75	1	2025-08-03 21:30:40.332099	2025-08-03 21:30:40.332099	17
325	\N	101	\N	2025-06-09	1263.72	1	2025-08-03 21:30:40.819592	2025-08-03 21:30:40.819592	17
326	\N	101	\N	2025-06-11	512.47	1	2025-08-03 21:30:41.238053	2025-08-03 21:30:41.238053	17
327	\N	101	\N	2025-06-18	0.00	1	2025-08-03 21:30:41.707049	2025-08-03 21:30:41.707049	2
328	\N	101	\N	2025-06-23	821.22	1	2025-08-03 21:30:42.200758	2025-08-03 21:30:42.200758	17
329	\N	101	\N	2025-06-30	45.25	1	2025-08-03 21:30:42.794285	2025-08-03 21:30:42.794285	17
330	\N	44	\N	2025-07-29	2264.52	1	2025-08-03 21:30:43.331296	2025-08-03 21:30:43.331296	13
331	\N	57	\N	2025-01-02	2222.90	1	2025-08-03 21:30:43.809991	2025-08-03 21:30:43.809991	1
332	\N	57	\N	2025-01-13	0.00	1	2025-08-03 21:30:44.233489	2025-08-03 21:30:44.233489	2
333	\N	57	\N	2025-01-13	1936.90	1	2025-08-03 21:30:44.720593	2025-08-03 21:30:44.720593	1
334	\N	57	\N	2025-01-13	494.05	1	2025-08-03 21:30:45.309906	2025-08-03 21:30:45.309906	12
335	\N	57	\N	2025-01-14	206.75	1	2025-08-03 21:30:46.013277	2025-08-03 21:30:46.013277	1
336	\N	57	\N	2025-01-20	320.35	1	2025-08-03 21:30:46.656126	2025-08-03 21:30:46.656126	12
337	\N	57	\N	2025-01-22	574.60	1	2025-08-03 21:30:47.296813	2025-08-03 21:30:47.296813	12
338	\N	57	\N	2025-01-27	287.30	1	2025-08-03 21:30:48.05392	2025-08-03 21:30:48.05392	18
339	\N	57	\N	2025-01-29	287.30	1	2025-08-03 21:30:48.894171	2025-08-03 21:30:48.894171	12
340	\N	57	\N	2025-02-02	640.55	1	2025-08-03 21:30:49.63624	2025-08-03 21:30:49.63624	1
341	\N	57	\N	2025-02-10	1058.15	1	2025-08-03 21:30:50.305577	2025-08-03 21:30:50.305577	1
342	\N	57	\N	2025-02-10	858.15	1	2025-08-03 21:30:50.875335	2025-08-03 21:30:50.875335	12
343	\N	143	\N	2025-05-15	800.72	1	2025-08-03 21:30:51.597217	2025-08-03 21:30:51.597217	9
344	\N	143	\N	2025-05-23	162.07	1	2025-08-03 21:30:52.085914	2025-08-03 21:30:52.085914	1
345	\N	143	\N	2025-05-23	162.07	1	2025-08-03 21:30:52.507392	2025-08-03 21:30:52.507392	9
346	\N	143	\N	2025-06-02	105.72	1	2025-08-03 21:30:52.964174	2025-08-03 21:30:52.964174	18
347	\N	143	\N	2025-06-30	162.07	1	2025-08-03 21:30:53.451675	2025-08-03 21:30:53.451675	1
348	\N	143	\N	2025-07-21	162.07	1	2025-08-03 21:30:53.901642	2025-08-03 21:30:53.901642	1
349	\N	143	\N	2025-07-23	267.22	1	2025-08-03 21:30:54.419132	2025-08-03 21:30:54.419132	15
350	\N	143	\N	2025-07-23	162.07	1	2025-08-03 21:30:54.909706	2025-08-03 21:30:54.909706	9
351	\N	143	\N	2025-07-24	60.47	1	2025-08-03 21:30:55.421897	2025-08-03 21:30:55.421897	9
352	\N	143	\N	2025-07-29	275.00	1	2025-08-03 21:30:56.169802	2025-08-03 21:30:56.169802	9
353	\N	57	\N	2022-10-27	1060.00	1	2025-08-03 21:30:56.616765	2025-08-03 21:30:56.616765	5
354	\N	57	\N	2022-10-28	400.00	1	2025-08-03 21:30:57.059493	2025-08-03 21:30:57.059493	5
355	\N	57	\N	2022-11-01	400.00	1	2025-08-03 21:30:57.537504	2025-08-03 21:30:57.537504	5
356	\N	57	\N	2022-11-03	800.00	1	2025-08-03 21:30:58.026513	2025-08-03 21:30:58.026513	5
357	\N	57	\N	2022-11-09	1050.00	1	2025-08-03 21:30:58.498797	2025-08-03 21:30:58.498797	5
358	\N	57	\N	2022-11-11	400.00	1	2025-08-03 21:30:58.995251	2025-08-03 21:30:58.995251	5
359	\N	57	\N	2022-11-11	650.00	1	2025-08-03 21:30:59.475401	2025-08-03 21:30:59.475401	7
360	\N	57	\N	2022-11-16	800.00	1	2025-08-03 21:30:59.957688	2025-08-03 21:30:59.957688	5
361	\N	57	\N	2022-11-23	930.00	1	2025-08-03 21:31:00.39435	2025-08-03 21:31:00.39435	5
362	\N	57	\N	2022-11-30	310.00	1	2025-08-03 21:31:00.87419	2025-08-03 21:31:00.87419	5
363	\N	57	\N	2022-12-01	580.00	1	2025-08-03 21:31:01.371973	2025-08-03 21:31:01.371973	5
364	\N	57	\N	2022-12-01	550.00	1	2025-08-03 21:31:01.833332	2025-08-03 21:31:01.833332	7
365	\N	57	\N	2022-12-05	400.00	1	2025-08-03 21:31:02.251375	2025-08-03 21:31:02.251375	5
366	\N	57	\N	2022-12-08	0.00	1	2025-08-03 21:31:02.720716	2025-08-03 21:31:02.720716	2
367	\N	57	\N	2022-12-08	400.00	1	2025-08-03 21:31:03.200341	2025-08-03 21:31:03.200341	5
368	\N	57	\N	2022-12-12	400.00	1	2025-08-03 21:31:03.623008	2025-08-03 21:31:03.623008	5
369	\N	57	\N	2022-12-15	400.00	1	2025-08-03 21:31:04.185301	2025-08-03 21:31:04.185301	5
370	\N	57	\N	2022-12-20	800.00	1	2025-08-03 21:31:04.826267	2025-08-03 21:31:04.826267	5
371	\N	57	\N	2022-12-30	800.00	1	2025-08-03 21:31:05.254681	2025-08-03 21:31:05.254681	5
372	\N	57	\N	2022-12-30	625.00	1	2025-08-03 21:31:05.842752	2025-08-03 21:31:05.842752	7
373	\N	57	\N	2023-01-03	400.00	1	2025-08-03 21:31:06.346793	2025-08-03 21:31:06.346793	5
374	\N	57	\N	2023-01-05	400.00	1	2025-08-03 21:31:06.9262	2025-08-03 21:31:06.9262	5
375	\N	57	\N	2023-01-11	800.00	1	2025-08-03 21:31:07.532063	2025-08-03 21:31:07.532063	5
376	\N	57	\N	2023-01-19	800.00	1	2025-08-03 21:31:08.154204	2025-08-03 21:31:08.154204	5
\.


--
-- TOC entry 4932 (class 0 OID 90767)
-- Dependencies: 221
-- Data for Name: locations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.locations (id, name, status, created_at, updated_at) FROM stdin;
1	Pain Management	1	2025-08-02 11:18:01.552126	2025-08-02 11:18:01.552126
2	Nellis	1	2025-08-02 11:18:02.121209	2025-08-02 11:18:02.121209
3	Aliante	1	2025-08-02 11:18:03.63555	2025-08-02 11:18:03.63555
4	Green Valley	1	2025-08-02 11:18:04.381325	2025-08-02 11:18:04.381325
5	Rhodes Ranch	1	2025-08-02 11:18:05.450868	2025-08-02 11:18:05.450868
6	Delfina Simpson, APRN	1	2025-08-02 11:18:14.831228	2025-08-02 11:18:14.831228
7	Summerlin	1	2025-08-02 11:18:18.640317	2025-08-02 11:18:18.640317
8	Centennial	1	2025-08-02 11:18:24.188475	2025-08-02 11:18:24.188475
9	MRI - Nellis	1	2025-08-02 11:18:32.861593	2025-08-02 11:18:32.861593
10	Decatur	1	2025-08-02 13:49:54.364822	2025-08-02 13:49:54.364822
\.


--
-- TOC entry 4934 (class 0 OID 90772)
-- Dependencies: 223
-- Data for Name: patient_attorny_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.patient_attorny_log (id, patient_id, attorney_id, first_visit_date, created_at, updated_at, location_id, last_visit_date) FROM stdin;
1	108	43	2025-04-25	2025-08-03 19:42:20.778273	2025-08-03 19:42:20.778273	3	2025-06-05
2	141	44	2024-12-17	2025-08-03 19:42:21.169708	2025-08-03 19:42:21.169708	3	2025-06-13
3	189	44	2025-02-18	2025-08-03 19:42:21.589655	2025-08-03 19:42:21.589655	3	2025-06-03
4	93	45	2025-04-17	2025-08-03 19:42:22.119696	2025-08-03 19:42:22.119696	3	2025-06-09
5	190	46	2025-02-21	2025-08-03 19:42:22.510078	2025-08-03 19:42:22.510078	3	2025-06-09
6	79	46	2025-02-21	2025-08-03 19:42:22.974865	2025-08-03 19:42:22.974865	3	2025-06-09
7	72	47	2025-03-31	2025-08-03 19:42:23.350602	2025-08-03 19:42:23.350602	3	2025-06-09
8	110	48	2023-11-06	2025-08-03 19:42:23.916732	2025-08-03 19:42:23.916732	3	2025-06-03
9	77	49	2025-05-28	2025-08-03 19:42:24.310965	2025-08-03 19:42:24.310965	3	2025-06-13
10	127	50	2025-03-25	2025-08-03 19:42:24.781925	2025-08-03 19:42:24.781925	3	2025-06-02
11	84	50	2025-04-03	2025-08-03 19:42:25.226501	2025-08-03 19:42:25.226501	3	2025-06-13
12	124	51	2024-11-21	2025-08-03 19:42:25.821528	2025-08-03 19:42:25.821528	3	2025-06-10
13	59	52	2025-01-17	2025-08-03 19:42:26.424627	2025-08-03 19:42:26.424627	3	2025-06-03
14	148	52	2025-05-28	2025-08-03 19:42:26.940275	2025-08-03 19:42:26.940275	3	2025-06-10
15	24	53	2025-04-30	2025-08-03 19:42:27.595272	2025-08-03 19:42:27.595272	3	2025-06-10
16	161	54	2020-03-16	2025-08-03 19:42:28.124343	2025-08-03 19:42:28.124343	8	2025-06-06
17	165	44	2025-04-29	2025-08-03 19:42:28.650946	2025-08-03 19:42:28.650946	8	2025-06-02
18	47	47	2024-11-27	2025-08-03 19:42:29.233983	2025-08-03 19:42:29.233983	8	2025-06-02
19	191	48	2018-01-31	2025-08-03 19:42:29.750283	2025-08-03 19:42:29.750283	8	2025-06-13
20	103	50	2025-04-18	2025-08-03 19:42:30.259022	2025-08-03 19:42:30.259022	8	2025-06-03
21	174	44	2024-11-09	2025-08-03 19:42:30.715474	2025-08-03 19:42:30.715474	10	2025-06-13
22	192	44	2025-01-20	2025-08-03 19:42:31.389228	2025-08-03 19:42:31.389228	10	2025-06-02
23	185	44	2024-11-07	2025-08-03 19:42:31.893945	2025-08-03 19:42:31.893945	10	2025-06-12
24	193	55	2024-12-07	2025-08-03 19:42:32.308912	2025-08-03 19:42:32.308912	10	2025-06-09
25	76	56	2025-01-07	2025-08-03 19:42:32.741261	2025-08-03 19:42:32.741261	10	2025-06-12
26	194	57	2025-01-13	2025-08-03 19:42:33.670279	2025-08-03 19:42:33.670279	10	2025-06-09
27	195	44	2022-05-26	2025-08-03 19:42:34.078528	2025-08-03 19:42:34.078528	4	2025-06-06
28	35	44	2025-01-15	2025-08-03 19:42:34.636103	2025-08-03 19:42:34.636103	4	2025-06-06
29	101	44	2024-10-23	2025-08-03 19:42:35.040229	2025-08-03 19:42:35.040229	4	2025-06-05
30	196	44	2025-03-11	2025-08-03 19:42:35.536264	2025-08-03 19:42:35.536264	4	2025-06-13
31	197	44	2025-03-14	2025-08-03 19:42:35.965916	2025-08-03 19:42:35.965916	4	2025-06-04
32	160	44	2025-03-14	2025-08-03 19:42:36.493339	2025-08-03 19:42:36.493339	4	2025-06-04
33	198	44	2025-03-26	2025-08-03 19:42:36.892661	2025-08-03 19:42:36.892661	4	2025-06-02
34	199	44	2025-04-07	2025-08-03 19:42:37.324536	2025-08-03 19:42:37.324536	4	2025-06-09
35	200	44	2025-04-18	2025-08-03 19:42:37.808885	2025-08-03 19:42:37.808885	4	2025-06-09
36	118	44	2025-05-07	2025-08-03 19:42:38.280313	2025-08-03 19:42:38.280313	4	2025-06-06
37	63	44	2025-05-12	2025-08-03 19:42:38.807874	2025-08-03 19:42:38.807874	4	2025-06-10
38	115	44	2025-05-13	2025-08-03 19:42:39.293021	2025-08-03 19:42:39.293021	4	2025-06-12
39	201	45	2023-06-01	2025-08-03 19:42:39.744898	2025-08-03 19:42:39.744898	4	2025-06-09
40	202	58	2025-03-25	2025-08-03 19:42:40.102595	2025-08-03 19:42:40.102595	4	2025-06-03
41	203	59	2025-03-31	2025-08-03 19:42:40.472444	2025-08-03 19:42:40.472444	4	2025-06-03
42	204	52	2025-04-14	2025-08-03 19:42:40.828644	2025-08-03 19:42:40.828644	4	2025-06-09
43	49	57	2024-12-27	2025-08-03 19:42:41.312644	2025-08-03 19:42:41.312644	4	2025-06-06
44	205	57	2024-12-27	2025-08-03 19:42:41.673241	2025-08-03 19:42:41.673241	4	2025-06-06
45	206	60	2025-05-10	2025-08-03 19:42:42.019259	2025-08-03 19:42:42.019259	4	2025-06-12
46	187	61	2025-03-15	2025-08-03 19:42:42.423273	2025-08-03 19:42:42.423273	4	2025-06-07
47	85	44	2024-12-14	2025-08-03 19:42:42.918999	2025-08-03 19:42:42.918999	2	2025-06-14
48	10	44	2025-01-02	2025-08-03 19:42:43.449535	2025-08-03 19:42:43.449535	2	2025-06-09
49	7	44	2025-01-04	2025-08-03 19:42:43.917227	2025-08-03 19:42:43.917227	2	2025-06-03
50	208	44	2025-01-13	2025-08-03 19:42:44.245639	2025-08-03 19:42:44.245639	2	2025-06-11
51	32	44	2025-01-16	2025-08-03 19:42:44.690428	2025-08-03 19:42:44.690428	2	2025-06-05
52	176	44	2025-01-25	2025-08-03 19:42:45.069228	2025-08-03 19:42:45.069228	2	2025-06-05
53	209	44	2025-01-28	2025-08-03 19:42:45.631185	2025-08-03 19:42:45.631185	2	2025-06-02
54	133	44	2025-01-30	2025-08-03 19:42:46.100124	2025-08-03 19:42:46.100124	2	2025-06-11
55	145	44	2023-10-18	2025-08-03 19:42:46.883476	2025-08-03 19:42:46.883476	2	2025-06-12
56	64	44	2025-02-04	2025-08-03 19:42:47.384097	2025-08-03 19:42:47.384097	2	2025-06-03
57	210	44	2025-02-24	2025-08-03 19:42:47.765619	2025-08-03 19:42:47.765619	2	2025-06-04
58	211	44	2025-02-24	2025-08-03 19:42:48.171265	2025-08-03 19:42:48.171265	2	2025-06-04
59	212	44	2025-02-26	2025-08-03 19:42:48.631315	2025-08-03 19:42:48.631315	2	2025-06-14
60	83	44	2025-03-01	2025-08-03 19:42:49.023474	2025-08-03 19:42:49.023474	2	2025-06-02
61	178	44	2025-03-03	2025-08-03 19:42:49.463383	2025-08-03 19:42:49.463383	2	2025-06-03
62	213	44	2025-03-20	2025-08-03 19:42:49.850716	2025-08-03 19:42:49.850716	2	2025-06-06
63	143	44	2025-03-25	2025-08-03 19:42:50.251955	2025-08-03 19:42:50.251955	2	2025-06-13
64	214	44	2025-03-28	2025-08-03 19:42:50.666042	2025-08-03 19:42:50.666042	2	2025-06-06
65	50	44	2025-03-31	2025-08-03 19:42:51.404187	2025-08-03 19:42:51.404187	2	2025-06-13
66	109	44	2025-04-04	2025-08-03 19:42:51.985428	2025-08-03 19:42:51.985428	2	2025-06-12
67	20	44	2023-08-09	2025-08-03 19:42:52.511057	2025-08-03 19:42:52.511057	2	2025-06-11
68	8	44	2025-05-09	2025-08-03 19:42:53.002549	2025-08-03 19:42:53.002549	2	2025-06-06
69	106	44	2025-06-12	2025-08-03 19:42:53.414405	2025-08-03 19:42:53.414405	2	2025-06-13
70	215	45	2025-06-12	2025-08-03 19:42:53.853437	2025-08-03 19:42:53.853437	2	2025-06-12
71	216	62	2025-02-18	2025-08-03 19:42:54.242366	2025-08-03 19:42:54.242366	2	2025-06-12
72	102	63	2025-04-30	2025-08-03 19:42:54.772277	2025-08-03 19:42:54.772277	2	2025-06-04
73	217	64	2025-03-25	2025-08-03 19:42:55.19402	2025-08-03 19:42:55.19402	2	2025-06-10
74	218	65	2025-04-23	2025-08-03 19:42:55.630799	2025-08-03 19:42:55.630799	2	2025-06-02
75	219	66	2025-04-23	2025-08-03 19:42:56.055274	2025-08-03 19:42:56.055274	2	2025-06-13
76	22	67	2025-05-02	2025-08-03 19:42:56.48899	2025-08-03 19:42:56.48899	2	2025-06-10
77	137	68	2025-02-18	2025-08-03 19:42:56.883095	2025-08-03 19:42:56.883095	2	2025-06-06
78	220	49	2025-05-23	2025-08-03 19:42:57.41931	2025-08-03 19:42:57.41931	2	2025-06-06
79	119	55	2025-01-29	2025-08-03 19:42:57.793164	2025-08-03 19:42:57.793164	2	2025-06-14
80	51	55	2025-02-19	2025-08-03 19:42:58.25485	2025-08-03 19:42:58.25485	2	2025-06-13
81	221	69	2025-04-07	2025-08-03 19:42:58.726061	2025-08-03 19:42:58.726061	2	2025-06-09
82	184	50	2025-03-11	2025-08-03 19:42:59.333819	2025-08-03 19:42:59.333819	2	2025-06-14
83	167	50	2025-03-14	2025-08-03 19:42:59.789694	2025-08-03 19:42:59.789694	2	2025-06-02
84	13	70	2025-02-14	2025-08-03 19:43:00.346526	2025-08-03 19:43:00.346526	2	2025-06-06
85	222	51	2025-05-30	2025-08-03 19:43:00.789995	2025-08-03 19:43:00.789995	2	2025-06-06
86	90	57	2024-06-19	2025-08-03 19:43:01.281602	2025-08-03 19:43:01.281602	2	2025-06-10
87	223	61	2025-06-02	2025-08-03 19:43:01.93691	2025-08-03 19:43:01.93691	2	2025-06-02
88	164	44	2025-01-06	2025-08-03 19:43:02.366263	2025-08-03 19:43:02.366263	1	2025-06-05
89	126	44	2025-01-16	2025-08-03 19:43:02.803227	2025-08-03 19:43:02.803227	1	2025-06-03
90	60	44	2025-01-22	2025-08-03 19:43:03.340233	2025-08-03 19:43:03.340233	1	2025-06-10
91	226	44	2025-04-22	2025-08-03 19:43:03.721222	2025-08-03 19:43:03.721222	1	2025-06-12
92	227	44	2025-04-29	2025-08-03 19:43:04.076805	2025-08-03 19:43:04.076805	1	2025-06-03
93	228	44	2025-05-05	2025-08-03 19:43:04.585234	2025-08-03 19:43:04.585234	1	2025-06-04
94	229	44	2025-05-06	2025-08-03 19:43:05.067989	2025-08-03 19:43:05.067989	1	2025-06-12
95	230	44	2025-05-08	2025-08-03 19:43:05.431239	2025-08-03 19:43:05.431239	1	2025-06-03
96	172	44	2025-05-08	2025-08-03 19:43:05.815985	2025-08-03 19:43:05.815985	1	2025-06-03
97	231	44	2025-05-13	2025-08-03 19:43:06.403564	2025-08-03 19:43:06.403564	1	2025-06-10
98	149	44	2025-05-14	2025-08-03 19:43:06.794202	2025-08-03 19:43:06.794202	1	2025-06-11
99	232	44	2025-05-22	2025-08-03 19:43:07.319368	2025-08-03 19:43:07.319368	1	2025-06-04
100	233	71	2025-06-11	2025-08-03 19:43:07.788577	2025-08-03 19:43:07.788577	1	2025-06-11
101	121	71	2025-06-11	2025-08-03 19:43:08.137971	2025-08-03 19:43:08.137971	1	2025-06-11
102	116	72	2025-04-01	2025-08-03 19:43:08.684624	2025-08-03 19:43:08.684624	1	2025-06-03
103	234	50	2025-01-07	2025-08-03 19:43:09.234288	2025-08-03 19:43:09.234288	1	2025-06-04
104	81	57	2025-03-26	2025-08-03 19:43:09.75453	2025-08-03 19:43:09.75453	1	2025-06-10
105	235	73	2025-04-29	2025-08-03 19:43:10.101524	2025-08-03 19:43:10.101524	1	2025-06-05
106	236	73	2025-05-12	2025-08-03 19:43:10.459414	2025-08-03 19:43:10.459414	1	2025-06-09
107	94	61	2025-03-31	2025-08-03 19:43:10.895173	2025-08-03 19:43:10.895173	1	2025-06-02
108	129	44	2025-05-07	2025-08-03 19:43:11.491819	2025-08-03 19:43:11.491819	5	2025-06-10
109	239	44	2025-05-29	2025-08-03 19:43:11.867387	2025-08-03 19:43:11.867387	5	2025-06-09
110	240	44	2025-06-02	2025-08-03 19:43:12.229003	2025-08-03 19:43:12.229003	5	2025-06-09
111	29	44	2025-06-03	2025-08-03 19:43:12.643739	2025-08-03 19:43:12.643739	5	2025-06-03
112	241	45	2024-11-19	2025-08-03 19:43:13.057728	2025-08-03 19:43:13.057728	5	2025-06-05
113	242	74	2024-12-13	2025-08-03 19:43:13.43363	2025-08-03 19:43:13.43363	5	2025-06-11
114	97	75	2025-02-24	2025-08-03 19:43:13.85237	2025-08-03 19:43:13.85237	5	2025-06-13
115	243	50	2025-03-27	2025-08-03 19:43:14.301068	2025-08-03 19:43:14.301068	5	2025-06-10
116	244	52	2025-03-12	2025-08-03 19:43:14.694038	2025-08-03 19:43:14.694038	5	2025-06-11
117	238	76	2023-09-07	2025-08-03 19:43:15.11961	2025-08-03 19:43:15.11961	5	2025-06-13
118	171	57	2024-11-22	2025-08-03 19:43:15.583825	2025-08-03 19:43:15.583825	5	2025-06-10
119	182	57	2024-11-20	2025-08-03 19:43:15.984385	2025-08-03 19:43:15.984385	5	2025-06-02
120	245	61	2025-05-15	2025-08-03 19:43:16.437598	2025-08-03 19:43:16.437598	5	2025-06-04
121	55	44	2025-01-29	2025-08-03 19:43:16.855525	2025-08-03 19:43:16.855525	7	2025-06-06
122	183	44	2025-02-11	2025-08-03 19:43:17.294932	2025-08-03 19:43:17.294932	7	2025-06-11
123	246	44	2025-04-16	2025-08-03 19:43:17.67313	2025-08-03 19:43:17.67313	7	2025-06-04
124	153	44	2025-04-16	2025-08-03 19:43:18.106647	2025-08-03 19:43:18.106647	7	2025-06-04
125	144	44	2025-04-24	2025-08-03 19:43:18.493294	2025-08-03 19:43:18.493294	7	2025-06-03
126	247	44	2025-05-06	2025-08-03 19:43:19.017329	2025-08-03 19:43:19.017329	7	2025-06-02
127	248	44	2025-05-12	2025-08-03 19:43:19.597664	2025-08-03 19:43:19.597664	7	2025-06-13
128	249	45	2025-04-09	2025-08-03 19:43:20.123907	2025-08-03 19:43:20.123907	7	2025-06-04
129	250	52	2025-05-07	2025-08-03 19:43:20.688194	2025-08-03 19:43:20.688194	7	2025-06-11
130	132	57	2021-03-29	2025-08-03 19:43:21.107992	2025-08-03 19:43:21.107992	7	2025-06-11
131	46	61	2025-03-03	2025-08-03 19:43:21.822116	2025-08-03 19:43:21.822116	7	2025-06-10
\.


--
-- TOC entry 4936 (class 0 OID 90778)
-- Dependencies: 225
-- Data for Name: patient_location_log; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.patient_location_log (id, patient_id, location_id, first_visit_date, created_at, updated_at, last_visit_date) FROM stdin;
1	1	1	2025-01-07	2025-08-02 11:18:01.896633	2025-08-02 11:18:01.896633	2025-06-04
2	2	2	2025-03-25	2025-08-02 11:18:02.953211	2025-08-02 11:18:02.953211	2025-06-10
3	3	1	2025-04-16	2025-08-02 11:18:03.400693	2025-08-02 11:18:03.400693	2025-06-04
4	4	3	2025-06-10	2025-08-02 11:18:04.240169	2025-08-02 11:18:04.240169	2025-06-10
5	5	4	2019-03-01	2025-08-02 11:18:05.184543	2025-08-02 11:18:05.184543	2025-06-06
6	6	5	2018-01-23	2025-08-02 11:18:06.171031	2025-08-02 11:18:06.171031	2025-06-03
7	7	1	2025-01-04	2025-08-02 11:18:06.896238	2025-08-02 11:18:06.896238	2025-06-03
8	8	2	2025-05-09	2025-08-02 11:18:07.91177	2025-08-02 11:18:07.91177	2025-06-06
9	9	5	2024-12-13	2025-08-02 11:18:08.888455	2025-08-02 11:18:08.888455	2025-06-11
10	10	2	2025-01-02	2025-08-02 11:18:09.512178	2025-08-02 11:18:09.512178	2025-06-09
11	11	5	2025-06-09	2025-08-02 11:18:10.420706	2025-08-02 11:18:10.420706	2025-06-09
12	12	2	2025-05-30	2025-08-02 11:18:11.166392	2025-08-02 11:18:11.166392	2025-06-06
13	13	2	2025-02-14	2025-08-02 11:18:11.859016	2025-08-02 11:18:11.859016	2025-06-06
14	14	2	2025-06-13	2025-08-02 11:18:12.283326	2025-08-02 11:18:12.283326	2025-06-13
15	15	1	2025-04-23	2025-08-02 11:18:12.898855	2025-08-02 11:18:12.898855	2025-06-02
16	16	4	2023-06-01	2025-08-02 11:18:13.417534	2025-08-02 11:18:13.417534	2025-06-09
17	17	5	2025-03-12	2025-08-02 11:18:13.993776	2025-08-02 11:18:13.993776	2025-06-11
18	18	1	2025-06-11	2025-08-02 11:18:14.581071	2025-08-02 11:18:14.581071	2025-06-11
19	19	6	2025-05-12	2025-08-02 11:18:15.19231	2025-08-02 11:18:15.19231	2025-06-13
20	20	2	2023-08-09	2025-08-02 11:18:15.641369	2025-08-02 11:18:15.641369	2025-06-11
21	21	2	2018-12-03	2025-08-02 11:18:16.104799	2025-08-02 11:18:16.104799	2025-06-12
22	22	2	2025-05-02	2025-08-02 11:18:16.617578	2025-08-02 11:18:16.617578	2025-06-10
23	23	1	2025-05-08	2025-08-02 11:18:17.136216	2025-08-02 11:18:17.136216	2025-06-03
24	24	3	2025-04-30	2025-08-02 11:18:17.632453	2025-08-02 11:18:17.632453	2025-06-10
25	25	2	2025-04-28	2025-08-02 11:18:18.079797	2025-08-02 11:18:18.079797	2025-06-11
26	26	4	2025-03-26	2025-08-02 11:18:18.517944	2025-08-02 11:18:18.517944	2025-06-02
27	27	7	2025-04-30	2025-08-02 11:18:19.187765	2025-08-02 11:18:19.187765	2025-06-13
28	28	2	2025-06-13	2025-08-02 11:18:19.632789	2025-08-02 11:18:19.632789	2025-06-13
29	29	2	2025-06-03	2025-08-02 11:18:20.037324	2025-08-02 11:18:20.037324	2025-06-03
30	30	2	2025-05-23	2025-08-02 11:18:20.447353	2025-08-02 11:18:20.447353	2025-06-06
31	31	2	2025-06-04	2025-08-02 11:18:20.900167	2025-08-02 11:18:20.900167	2025-06-04
32	32	1	2025-01-16	2025-08-02 11:18:21.306668	2025-08-02 11:18:21.306668	2025-06-05
33	33	4	2025-06-12	2025-08-02 11:18:21.750743	2025-08-02 11:18:21.750743	2025-06-12
34	34	4	2022-05-26	2025-08-02 11:18:22.216009	2025-08-02 11:18:22.216009	2025-06-06
35	35	4	2025-01-15	2025-08-02 11:18:22.610965	2025-08-02 11:18:22.610965	2025-06-06
36	36	5	2025-05-15	2025-08-02 11:18:23.022286	2025-08-02 11:18:23.022286	2025-06-04
37	37	4	2025-06-02	2025-08-02 11:18:23.468338	2025-08-02 11:18:23.468338	2025-06-02
38	38	5	2025-05-29	2025-08-02 11:18:24.079936	2025-08-02 11:18:24.079936	2025-06-09
39	39	8	2018-04-21	2025-08-02 11:18:24.555309	2025-08-02 11:18:24.555309	2025-06-05
40	40	8	2018-05-08	2025-08-02 11:18:25.006764	2025-08-02 11:18:25.006764	2025-06-02
41	41	7	2025-05-07	2025-08-02 11:18:25.498455	2025-08-02 11:18:25.498455	2025-06-11
42	42	2	2018-10-11	2025-08-02 11:18:25.90619	2025-08-02 11:18:25.90619	2025-06-09
43	43	5	2018-01-05	2025-08-02 11:18:26.372174	2025-08-02 11:18:26.372174	2025-06-06
44	44	5	2021-06-23	2025-08-02 11:18:27.018408	2025-08-02 11:18:27.018408	2025-06-02
45	45	2	2025-03-28	2025-08-02 11:18:27.450572	2025-08-02 11:18:27.450572	2025-06-06
46	46	7	2025-03-03	2025-08-02 11:18:27.99032	2025-08-02 11:18:27.99032	2025-06-10
47	47	8	2024-11-27	2025-08-02 11:18:28.612267	2025-08-02 11:18:28.612267	2025-06-02
48	48	2	2025-02-24	2025-08-02 11:18:29.156221	2025-08-02 11:18:29.156221	2025-06-04
49	49	4	2024-12-27	2025-08-02 11:18:29.479623	2025-08-02 11:18:29.479623	2025-06-06
50	50	2	2025-03-31	2025-08-02 11:18:30.032816	2025-08-02 11:18:30.032816	2025-06-13
51	51	2	2025-02-19	2025-08-02 11:18:30.50716	2025-08-02 11:18:30.50716	2025-06-13
52	52	7	2025-05-08	2025-08-02 11:18:30.909151	2025-08-02 11:18:30.909151	2025-06-02
53	53	8	2020-10-02	2025-08-02 11:18:31.357391	2025-08-02 11:18:31.357391	2025-06-06
54	54	1	2025-04-29	2025-08-02 11:18:31.826453	2025-08-02 11:18:31.826453	2025-06-03
55	55	7	2025-01-29	2025-08-02 11:18:32.206261	2025-08-02 11:18:32.206261	2025-06-06
56	56	2	2025-06-13	2025-08-02 11:18:32.580744	2025-08-02 11:18:32.580744	2025-06-13
57	57	9	2025-06-02	2025-08-02 11:18:33.245912	2025-08-02 11:18:33.245912	2025-06-02
58	58	8	2025-05-09	2025-08-02 11:18:33.583176	2025-08-02 11:18:33.583176	2025-06-12
59	59	3	2025-01-17	2025-08-02 11:18:34.128326	2025-08-02 11:18:34.128326	2025-06-03
60	60	1	2025-01-22	2025-08-02 11:18:34.854015	2025-08-02 11:18:34.854015	2025-06-10
61	61	2	2024-12-11	2025-08-02 11:18:35.218559	2025-08-02 11:18:35.218559	2025-06-11
62	62	8	2025-06-02	2025-08-02 11:18:35.565226	2025-08-02 11:18:35.565226	2025-06-06
63	63	2	2025-05-12	2025-08-02 11:18:36.133371	2025-08-02 11:18:36.133371	2025-06-10
64	64	2	2025-02-04	2025-08-02 11:18:36.518913	2025-08-02 11:18:36.518913	2025-06-03
65	65	2	2025-02-24	2025-08-02 11:18:36.935963	2025-08-02 11:18:36.935963	2025-06-04
66	66	4	2024-12-27	2025-08-02 11:18:37.375466	2025-08-02 11:18:37.375466	2025-06-06
67	67	4	2025-04-07	2025-08-02 11:18:37.74952	2025-08-02 11:18:37.74952	2025-06-09
68	68	8	2024-02-08	2025-08-02 11:18:38.229781	2025-08-02 11:18:38.229781	2025-06-03
69	69	2	2025-04-23	2025-08-02 11:18:38.624794	2025-08-02 11:18:38.624794	2025-06-11
70	70	2	2025-06-09	2025-08-02 11:18:39.172776	2025-08-02 11:18:39.172776	2025-06-09
71	71	4	2025-03-31	2025-08-02 11:18:39.621935	2025-08-02 11:18:39.621935	2025-06-03
72	72	3	2025-03-31	2025-08-02 11:18:40.013493	2025-08-02 11:18:40.013493	2025-06-09
73	73	2	2024-04-16	2025-08-02 11:18:40.455953	2025-08-02 11:18:40.455953	2025-06-09
74	74	2	2025-02-26	2025-08-02 11:18:40.921239	2025-08-02 11:18:40.921239	2025-06-14
75	75	2	2025-03-20	2025-08-02 11:18:41.35221	2025-08-02 11:18:41.35221	2025-06-06
76	76	1	2025-01-07	2025-08-02 11:18:41.944934	2025-08-02 11:18:41.944934	2025-06-12
77	77	3	2025-05-28	2025-08-02 11:18:42.551892	2025-08-02 11:18:42.551892	2025-06-13
78	78	1	2024-12-27	2025-08-02 11:18:43.094696	2025-08-02 11:18:43.094696	2025-06-04
79	79	3	2025-02-21	2025-08-02 11:18:43.766997	2025-08-02 11:18:43.766997	2025-06-09
80	80	3	2025-02-21	2025-08-02 11:18:44.213688	2025-08-02 11:18:44.213688	2025-06-09
81	81	5	2025-03-26	2025-08-02 11:18:44.505034	2025-08-02 11:18:44.505034	2025-06-10
82	82	1	2025-05-06	2025-08-02 11:18:45.075098	2025-08-02 11:18:45.075098	2025-06-02
83	83	2	2025-03-01	2025-08-02 11:18:45.749226	2025-08-02 11:18:45.749226	2025-06-02
84	84	3	2025-04-03	2025-08-02 11:18:46.192963	2025-08-02 11:18:46.192963	2025-06-13
85	85	2	2024-12-14	2025-08-02 11:18:46.626256	2025-08-02 11:18:46.626256	2025-06-14
86	86	8	2018-01-31	2025-08-02 11:18:47.059069	2025-08-02 11:18:47.059069	2025-06-13
87	87	8	2018-01-09	2025-08-02 11:18:47.469644	2025-08-02 11:18:47.469644	2025-06-13
88	88	3	2023-02-28	2025-08-02 11:18:47.774552	2025-08-02 11:18:47.774552	2025-06-02
89	89	7	2025-04-09	2025-08-02 11:18:48.148714	2025-08-02 11:18:48.148714	2025-06-04
90	90	2	2024-06-19	2025-08-02 11:18:48.545009	2025-08-02 11:18:48.545009	2025-06-10
91	91	2	2025-06-02	2025-08-02 11:18:49.030583	2025-08-02 11:18:49.030583	2025-06-09
92	92	4	2025-03-14	2025-08-02 11:18:49.685254	2025-08-02 11:18:49.685254	2025-06-04
93	93	3	2025-04-17	2025-08-02 11:18:50.136456	2025-08-02 11:18:50.136456	2025-06-09
94	94	5	2025-03-31	2025-08-02 11:18:50.637677	2025-08-02 11:18:50.637677	2025-06-02
95	95	6	2025-02-18	2025-08-02 11:18:51.086218	2025-08-02 11:18:51.086218	2025-06-12
96	96	5	2023-09-07	2025-08-02 11:18:51.430944	2025-08-02 11:18:51.430944	2025-06-13
97	97	5	2025-02-24	2025-08-02 11:18:51.838415	2025-08-02 11:18:51.838415	2025-06-13
98	98	1	2025-04-22	2025-08-02 11:18:52.246028	2025-08-02 11:18:52.246028	2025-06-12
99	99	2	2025-04-07	2025-08-02 11:18:52.583761	2025-08-02 11:18:52.583761	2025-06-09
100	100	2	2025-06-10	2025-08-02 11:18:52.99448	2025-08-02 11:18:52.99448	2025-06-10
101	101	1	2024-10-23	2025-08-02 11:18:53.39101	2025-08-02 11:18:53.39101	2025-06-05
102	102	2	2025-04-30	2025-08-02 11:18:53.964548	2025-08-02 11:18:53.964548	2025-06-04
103	103	4	2025-04-18	2025-08-02 11:18:54.443718	2025-08-02 11:18:54.443718	2025-06-03
104	104	4	2025-04-03	2025-08-02 11:18:54.909201	2025-08-02 11:18:54.909201	2025-06-13
105	105	2	2025-01-28	2025-08-02 11:18:55.327032	2025-08-02 11:18:55.327032	2025-06-02
106	106	2	2025-06-12	2025-08-02 11:18:55.702349	2025-08-02 11:18:55.702349	2025-06-13
107	107	4	2025-03-11	2025-08-02 11:18:56.118525	2025-08-02 11:18:56.118525	2025-06-13
108	108	3	2025-04-25	2025-08-02 11:18:56.503058	2025-08-02 11:18:56.503058	2025-06-05
109	109	2	2025-04-04	2025-08-02 11:18:57.051891	2025-08-02 11:18:57.051891	2025-06-12
110	110	3	2023-11-06	2025-08-02 11:18:57.461241	2025-08-02 11:18:57.461241	2025-06-03
111	111	4	2024-06-04	2025-08-02 11:18:57.934304	2025-08-02 11:18:57.934304	2025-06-06
112	112	5	2025-03-27	2025-08-02 11:18:58.422186	2025-08-02 11:18:58.422186	2025-06-10
113	113	2	2022-11-11	2025-08-02 11:18:58.809831	2025-08-02 11:18:58.809831	2025-06-06
114	114	2	2018-07-11	2025-08-02 11:18:59.299441	2025-08-02 11:18:59.299441	2025-06-09
115	115	2	2025-05-13	2025-08-02 11:18:59.787337	2025-08-02 11:18:59.787337	2025-06-12
116	116	1	2025-04-01	2025-08-02 11:19:00.231717	2025-08-02 11:19:00.231717	2025-06-03
117	117	2	2025-05-21	2025-08-02 11:19:00.587552	2025-08-02 11:19:00.587552	2025-06-09
118	118	9	2025-05-07	2025-08-02 11:19:01.089522	2025-08-02 11:19:01.089522	2025-06-06
119	119	2	2025-01-29	2025-08-02 11:19:01.498524	2025-08-02 11:19:01.498524	2025-06-14
120	120	3	2025-02-18	2025-08-02 11:19:01.927968	2025-08-02 11:19:01.927968	2025-06-03
121	121	1	2025-06-11	2025-08-02 11:19:02.374703	2025-08-02 11:19:02.374703	2025-06-11
122	122	5	2018-04-23	2025-08-02 11:19:02.770597	2025-08-02 11:19:02.770597	2025-06-12
123	123	4	2018-05-22	2025-08-02 11:19:03.151474	2025-08-02 11:19:03.151474	2025-06-03
124	124	3	2024-11-21	2025-08-02 11:19:03.549482	2025-08-02 11:19:03.549482	2025-06-10
125	125	2	2021-05-20	2025-08-02 11:19:04.009848	2025-08-02 11:19:04.009848	2025-06-06
126	126	3	2025-01-16	2025-08-02 11:19:04.548967	2025-08-02 11:19:04.548967	2025-06-03
127	127	8	2025-03-25	2025-08-02 11:19:05.072045	2025-08-02 11:19:05.072045	2025-06-02
128	128	4	2025-03-25	2025-08-02 11:19:05.481035	2025-08-02 11:19:05.481035	2025-06-03
129	129	5	2025-05-07	2025-08-02 11:19:05.866724	2025-08-02 11:19:05.866724	2025-06-10
130	130	2	2025-04-23	2025-08-02 11:19:06.266616	2025-08-02 11:19:06.266616	2025-06-13
131	131	3	2025-02-28	2025-08-02 11:19:06.733027	2025-08-02 11:19:06.733027	2025-06-13
132	132	7	2021-03-29	2025-08-02 11:19:07.217656	2025-08-02 11:19:07.217656	2025-06-11
133	133	2	2025-01-30	2025-08-02 11:19:07.571547	2025-08-02 11:19:07.571547	2025-06-11
134	134	1	2025-05-13	2025-08-02 11:19:07.981972	2025-08-02 11:19:07.981972	2025-06-10
135	135	7	2024-12-07	2025-08-02 11:19:08.676865	2025-08-02 11:19:08.676865	2025-06-09
136	136	4	2025-04-14	2025-08-02 11:19:09.309567	2025-08-02 11:19:09.309567	2025-06-09
137	137	2	2025-02-18	2025-08-02 11:19:09.62136	2025-08-02 11:19:09.62136	2025-06-06
138	138	1	2025-04-18	2025-08-02 11:19:09.970403	2025-08-02 11:19:09.970403	2025-06-09
139	139	1	2025-01-13	2025-08-02 11:19:10.377446	2025-08-02 11:19:10.377446	2025-06-11
140	140	4	2025-06-02	2025-08-02 11:19:10.765291	2025-08-02 11:19:10.765291	2025-06-02
141	141	3	2024-12-17	2025-08-02 11:19:11.399501	2025-08-02 11:19:11.399501	2025-06-13
142	142	8	2018-01-04	2025-08-02 11:19:11.915885	2025-08-02 11:19:11.915885	2025-06-10
143	143	2	2025-03-25	2025-08-02 11:19:12.269673	2025-08-02 11:19:12.269673	2025-06-13
144	144	7	2025-04-24	2025-08-02 11:19:12.839386	2025-08-02 11:19:12.839386	2025-06-03
145	145	2	2023-10-18	2025-08-02 11:19:13.307134	2025-08-02 11:19:13.307134	2025-06-12
146	146	3	2024-12-17	2025-08-02 11:19:13.772175	2025-08-02 11:19:13.772175	2025-06-13
147	147	7	2021-07-19	2025-08-02 11:19:14.183755	2025-08-02 11:19:14.183755	2025-06-04
148	148	9	2025-05-28	2025-08-02 11:19:14.649224	2025-08-02 11:19:14.649224	2025-06-10
149	149	1	2025-05-14	2025-08-02 11:19:14.988854	2025-08-02 11:19:14.988854	2025-06-11
150	150	8	2018-03-30	2025-08-02 11:19:15.438966	2025-08-02 11:19:15.438966	2025-06-09
151	151	8	2021-07-27	2025-08-02 11:19:15.804637	2025-08-02 11:19:15.804637	2025-06-04
152	152	1	2025-06-02	2025-08-02 11:19:16.361211	2025-08-02 11:19:16.361211	2025-06-02
153	153	1	2025-04-16	2025-08-02 11:19:17.024093	2025-08-02 11:19:17.024093	2025-06-04
154	154	2	2022-01-26	2025-08-02 11:19:17.451395	2025-08-02 11:19:17.451395	2025-06-04
155	155	1	2025-01-20	2025-08-02 11:19:17.914806	2025-08-02 11:19:17.914806	2025-06-02
156	156	3	2025-05-22	2025-08-02 11:19:18.313049	2025-08-02 11:19:18.313049	2025-06-04
157	157	4	2024-02-02	2025-08-02 11:19:18.674573	2025-08-02 11:19:18.674573	2025-06-06
158	158	5	2022-05-13	2025-08-02 11:19:19.075782	2025-08-02 11:19:19.075782	2025-06-06
159	159	7	2025-04-29	2025-08-02 11:19:19.581718	2025-08-02 11:19:19.581718	2025-06-05
160	160	4	2025-03-14	2025-08-02 11:19:20.005713	2025-08-02 11:19:20.005713	2025-06-04
161	161	8	2020-03-16	2025-08-02 11:19:20.514528	2025-08-02 11:19:20.514528	2025-06-06
162	162	5	2024-11-19	2025-08-02 11:19:20.928007	2025-08-02 11:19:20.928007	2025-06-05
163	163	8	2025-06-02	2025-08-02 11:19:21.373606	2025-08-02 11:19:21.373606	2025-06-02
164	164	1	2025-01-06	2025-08-02 11:19:21.828657	2025-08-02 11:19:21.828657	2025-06-05
165	165	8	2025-04-29	2025-08-02 11:19:22.26274	2025-08-02 11:19:22.26274	2025-06-02
166	166	1	2025-05-06	2025-08-02 11:19:22.71651	2025-08-02 11:19:22.71651	2025-06-12
167	167	2	2025-03-14	2025-08-02 11:19:23.126592	2025-08-02 11:19:23.126592	2025-06-02
168	168	2	2025-03-08	2025-08-02 11:19:23.573545	2025-08-02 11:19:23.573545	2025-06-07
169	169	8	2025-06-12	2025-08-02 11:19:23.985162	2025-08-02 11:19:23.985162	2025-06-12
170	170	1	2025-05-05	2025-08-02 11:19:24.359501	2025-08-02 11:19:24.359501	2025-06-04
171	171	5	2024-11-22	2025-08-02 11:19:24.748885	2025-08-02 11:19:24.748885	2025-06-10
172	172	1	2025-05-08	2025-08-02 11:19:25.076871	2025-08-02 11:19:25.076871	2025-06-03
173	173	4	2025-05-29	2025-08-02 11:19:25.44353	2025-08-02 11:19:25.44353	2025-06-09
174	174	7	2024-11-09	2025-08-02 11:19:25.86742	2025-08-02 11:19:25.86742	2025-06-13
175	175	2	2025-06-12	2025-08-02 11:19:26.262241	2025-08-02 11:19:26.262241	2025-06-12
176	176	2	2025-01-25	2025-08-02 11:19:26.705852	2025-08-02 11:19:26.705852	2025-06-05
177	177	2	2024-10-15	2025-08-02 11:19:27.126992	2025-08-02 11:19:27.126992	2025-06-13
178	178	2	2025-03-03	2025-08-02 11:19:27.512692	2025-08-02 11:19:27.512692	2025-06-03
179	179	3	2018-06-18	2025-08-02 11:19:27.884474	2025-08-02 11:19:27.884474	2025-06-06
180	180	7	2025-01-13	2025-08-02 11:19:28.305839	2025-08-02 11:19:28.305839	2025-06-09
181	181	4	2025-05-10	2025-08-02 11:19:28.626232	2025-08-02 11:19:28.626232	2025-06-12
182	182	5	2024-11-20	2025-08-02 11:19:29.07334	2025-08-02 11:19:29.07334	2025-06-02
183	183	7	2025-02-11	2025-08-02 11:19:29.458206	2025-08-02 11:19:29.458206	2025-06-11
184	184	2	2025-03-11	2025-08-02 11:19:29.856337	2025-08-02 11:19:29.856337	2025-06-14
185	185	7	2024-11-07	2025-08-02 11:19:30.217357	2025-08-02 11:19:30.217357	2025-06-12
186	186	1	2025-05-12	2025-08-02 11:19:30.615909	2025-08-02 11:19:30.615909	2025-06-09
187	187	5	2025-03-15	2025-08-02 11:19:31.036453	2025-08-02 11:19:31.036453	2025-06-07
188	188	5	2021-08-12	2025-08-02 11:19:31.434968	2025-08-02 11:19:31.434968	2025-06-05
\.


--
-- TOC entry 4938 (class 0 OID 90784)
-- Dependencies: 227
-- Data for Name: patients; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.patients (id, external_mrn, first_name, middle_name, last_name, dob, email, phone_number, status, created_at, updated_at, gender) FROM stdin;
1	ALVJO014	Jose	Arturo	Alvarez	2007-02-14	Ealvarez512@gmail.com	702-875-3283	1	2025-08-02 11:18:01.751952	2025-08-02 11:18:01.751952	male
2	ALVMA024	Maria	Lourdes	Alvarez	1968-02-19		702-640-9566	1	2025-08-02 11:18:02.681081	2025-08-02 11:18:02.681081	female
3	AMAJU003	Juan	C Tomax	Amaxtal	1995-11-05	Juancarlostomax00@gmail.com	702-826-9633	1	2025-08-02 11:18:03.153305	2025-08-02 11:18:03.153305	male
4	ANKBR001	Brian		Ankrom	2007-04-08		702-807-5335	1	2025-08-02 11:18:04.001289	2025-08-02 11:18:04.001289	male
5	KINYV000	Yvonne	Michele	Apler	1955-03-03	kinanewel@aol.com	702-701-6233	1	2025-08-02 11:18:04.750168	2025-08-02 11:18:04.750168	female
6	APPLE000	Leroy	Theodric	Applin	1971-12-23		702-265-9181	1	2025-08-02 11:18:05.810683	2025-08-02 11:18:05.810683	male
7	AMAYE001	Yeimy		Arias-Oquindo	1997-09-12	yariasoquendo@gmail.com	702-972-8776	1	2025-08-02 11:18:06.591769	2025-08-02 11:18:06.591769	female
8	AVISA000	Sabiel		Avila Perez	2006-01-20	vincettalangabriel@gmail.com	702-980-9720	1	2025-08-02 11:18:07.474118	2025-08-02 11:18:07.474118	male
9	BASWE000	Wendy	Carolina	Basto	1987-04-01	Wendy.hoyos87@gmail.com	702-477-5419	1	2025-08-02 11:18:08.42885	2025-08-02 11:18:08.42885	female
10	OZANE000	Nectali		Benavides Osorio	1981-05-06		702-824-6167	1	2025-08-02 11:18:09.276851	2025-08-02 11:18:09.276851	male
11	BERDA003	Dana		Berkson	1971-04-11	smilingservers@gmail.com	818-425-0787	1	2025-08-02 11:18:09.981016	2025-08-02 11:18:09.981016	
12	BOLGL000	Gloria	Angelicia	Bolanos	1953-08-01	gloriabolanos@yahoo.com	702-561-7422	1	2025-08-02 11:18:10.796833	2025-08-02 11:18:10.796833	female
13	BONLO002	Lorenzo		Bonucci	1998-01-07		725-293-2875	1	2025-08-02 11:18:11.447134	2025-08-02 11:18:11.447134	male
14	BOUGE003	George		Bouligny	1955-01-12	gbouligny88@gmail.com	725-314-3348	1	2025-08-02 11:18:12.10758	2025-08-02 11:18:12.10758	male
15	BRILA001	Lazaro	O	Brizuela Gonzalez	1995-11-03	Lazarobrizuela93@gmail.com	702-741-3771	1	2025-08-02 11:18:12.670771	2025-08-02 11:18:12.670771	male
16	BROAM005	Amanda	Rose	Brown	1995-03-17	Amrosevrown@gmail.com	909-913-9466	1	2025-08-02 11:18:13.200313	2025-08-02 11:18:13.200313	female
17	MUNER002	Erick	Alejandro	Camey-Munoz	1988-06-04		702-858-4131	1	2025-08-02 11:18:13.732192	2025-08-02 11:18:13.732192	male
18	CANIV000	Ivonne	Kassandra	Candelario Diaz	1998-08-17		702-238-6784	1	2025-08-02 11:18:14.266278	2025-08-02 11:18:14.266278	female
19	CARGL002	Gloria	Miriam	Cardoza-Huezo	1979-10-31	gloriamiriam888@gmail.com	818-335-6442	1	2025-08-02 11:18:15.027265	2025-08-02 11:18:15.027265	female
20	CASHO000	Horacio		Castellanos Santos	1975-01-02		702-742-6929	1	2025-08-02 11:18:15.366086	2025-08-02 11:18:15.366086	male
21	CASNO000	Noe		Castillo	1989-05-24	N.CASTILLO18@YAHOO.COM	702-708-6830	1	2025-08-02 11:18:15.935014	2025-08-02 11:18:15.935014	male
22	CERNA002	Narciso		Cervantes	1973-07-30		702-767-8575	1	2025-08-02 11:18:16.381417	2025-08-02 11:18:16.381417	male
23	JAIJH000	Jhon	Jairo	Chalares Arboleda	1987-04-02		747-245-9148	1	2025-08-02 11:18:16.92343	2025-08-02 11:18:16.92343	male
24	CHAJA015	Jaylah		Chavarria	2020-08-17	jabigaail@gmail.com	702-493-2898	1	2025-08-02 11:18:17.428416	2025-08-02 11:18:17.428416	female
25	COLAL011	Aliyaa	Denay	Collins	2001-07-14	aliyaacollins3@gmail.com 	702-793-1035	1	2025-08-02 11:18:17.911834	2025-08-02 11:18:17.911834	female
26	COMRO000	Ross	M	Conway	1981-08-26		702-481-0092	1	2025-08-02 11:18:18.274073	2025-08-02 11:18:18.274073	male
27	COOBE001	Bernice		Cooper	1983-07-18		702-761-1826	1	2025-08-02 11:18:19.022238	2025-08-02 11:18:19.022238	female
28	COPLE000	Leilani		Coppedge	1999-01-26		702-370-7607	1	2025-08-02 11:18:19.470093	2025-08-02 11:18:19.470093	female
29	CORDA005	Dania		Corbalan-Batista	1966-11-18		702-934-4954	1	2025-08-02 11:18:19.812719	2025-08-02 11:18:19.812719	female
30	CORJU009	Juan	Carlos	Corona Gonzalez	1989-06-09		702-786-5255	1	2025-08-02 11:18:20.273823	2025-08-02 11:18:20.273823	
31	E00AM000	Amram		Coronado	2013-10-23		702-401-4263	1	2025-08-02 11:18:20.627826	2025-08-02 11:18:20.627826	male
32	COROS006	Oscar		Corral	2007-07-08		702-955-2356	1	2025-08-02 11:18:21.124707	2025-08-02 11:18:21.124707	male
33	CORJE017	Jesus		Cortes	1997-09-11		801-821-8446	1	2025-08-02 11:18:21.54467	2025-08-02 11:18:21.54467	male
34	CUEDA000	David	Nelson Marck Anthony	Cueva-Llanos	1990-02-12	davidnmacueva@live.com	702-415-0423	1	2025-08-02 11:18:22.042359	2025-08-02 11:18:22.042359	male
35	CUEKE000	Kevin		Cueva-Llanos	1991-05-11	kevinejohnathan@gmail.com	702-604-5780	1	2025-08-02 11:18:22.423302	2025-08-02 11:18:22.423302	male
36	DAVTE002	Teresita	De Jesus	Davidson	1964-04-27	teri_dvdsn@yahoo.com	702-762-6770	1	2025-08-02 11:18:22.827236	2025-08-02 11:18:22.827236	female
37	DEGDU000	Duran		Degonzales	1989-06-06	djsanlv702@gmail.com 	702-417-1839	1	2025-08-02 11:18:23.224286	2025-08-02 11:18:23.224286	male
38	DINJU000	Juliana	Tuong VI	Dinh	2001-02-16	jdinh1590@gmail.com	702-372-3230	1	2025-08-02 11:18:23.832343	2025-08-02 11:18:23.832343	female
39	DRERO000	Robert	Fred	Drexler	1955-05-12	robertc3457@gmail.com	516-729-9840	1	2025-08-02 11:18:24.395076	2025-08-02 11:18:24.395076	male
40	DUDJA002	J	Lawton	DuBiago	1954-03-26		702-354-8542	1	2025-08-02 11:18:24.821878	2025-08-02 11:18:24.821878	male
41	ESCEM001	Emma	Evelyne	Escamilla	2007-01-03	Emmavegas2007@icloud.com	702-289-7368	1	2025-08-02 11:18:25.202648	2025-08-02 11:18:25.202648	female
42	ESTEL000	Eliazar		Estrada-Navarrete	1984-04-17	bbanuleos77@yahoo.com 	702-701-1866	1	2025-08-02 11:18:25.734306	2025-08-02 11:18:25.734306	male
43	EVEBR001	Brandon		Evenson	1982-06-30	bevenson31@gmail.com	702-882-7127	1	2025-08-02 11:18:26.136555	2025-08-02 11:18:26.136555	male
44	FISRA001	Randy		Fisher	1962-10-11	Ftazzazz1@aol.com	702-592-8197	1	2025-08-02 11:18:26.747697	2025-08-02 11:18:26.747697	male
45	??0MI000	Miriam	Zamira	Flores Cabrera	2005-01-27	fmiri452@gmail.com	702-809-2152	1	2025-08-02 11:18:27.244586	2025-08-02 11:18:27.244586	female
46	FLOMA032	Marcos		Flores	2011-11-14		702-764-9129	1	2025-08-02 11:18:27.809604	2025-08-02 11:18:27.809604	male
47	FLORI003	Ricardo		Flores	1982-01-08		702-665-3676	1	2025-08-02 11:18:28.467659	2025-08-02 11:18:28.467659	male
48	FOLBE000	Burton	Alan	Folkart	1961-01-11	folkartburton329@gmail.com	702-955-5252ext521	1	2025-08-02 11:18:28.900064	2025-08-02 11:18:28.900064	male
49	FRAEL001	Elyssa		Franco	1998-03-16	elyssafranco_16@gmail.com	702-761-9635	1	2025-08-02 11:18:29.334395	2025-08-02 11:18:29.334395	female
50	PERYA005	Yanila		Garcia Perez	1996-03-23	Pyamilegacira48@gamil.con	702-964-4686	1	2025-08-02 11:18:29.674868	2025-08-02 11:18:29.674868	female
51	GARAL022	Alberto		Garcia-Alvarez	1992-02-28	Garciaalberto8228@gmail.com	702-771-3180	1	2025-08-02 11:18:30.256695	2025-08-02 11:18:30.256695	male
52	GARJO050	Jose Alberto		Garcia	1993-01-03		702-561-8835	1	2025-08-02 11:18:30.782055	2025-08-02 11:18:30.782055	male
53	GAREL009	Elizabeth		Garr	2008-03-11		702-822-0208	1	2025-08-02 11:18:31.10901	2025-08-02 11:18:31.10901	female
54	COSMI002	Miguel	Alejandro	Gomez Costa	1996-12-30	Miguelgomez9625@icloud.com	305-391-0038	1	2025-08-02 11:18:31.605053	2025-08-02 11:18:31.605053	male
55	GOMAL010	Alejandro		Gomez-Cordova	1970-08-26	agomez736@yahoo.com	702-210-9079	1	2025-08-02 11:18:32.024699	2025-08-02 11:18:32.024699	male
56	GOMNA003	Naithan		Gomez	1999-12-10	naithangomez123@gmail.com	702-762-7987	1	2025-08-02 11:18:32.416112	2025-08-02 11:18:32.416112	
57	GONAL021	Alexandra	S	Gonzalez	2004-08-20	sarahiagonzalez2@gmail.com	702-683-2726	1	2025-08-02 11:18:33.07382	2025-08-02 11:18:33.07382	female
58	GONRO010	Rose	M	Gonzalez	1984-04-17	ricanroseg@gmail.com	702-409-3595	1	2025-08-02 11:18:33.427832	2025-08-02 11:18:33.427832	female
59	GREBR009	Braiden		Green	1985-05-31		702-379-7392	1	2025-08-02 11:18:33.810234	2025-08-02 11:18:33.810234	male
60	GRMJE000	Jeffery		Grmoja	1958-01-16	bigjeff7676@gmail.com	510-508-4394	1	2025-08-02 11:18:34.622974	2025-08-02 11:18:34.622974	male
61	GUAVI000	Virgilia De Maria		Guadron	1976-07-08	victoriaguadron@gmail.com	408-599-4485	1	2025-08-02 11:18:35.0472	2025-08-02 11:18:35.0472	female
62	GUEJE003	Jesse	G	Guerena	1948-09-04		626-617-9445	1	2025-08-02 11:18:35.398306	2025-08-02 11:18:35.398306	male
63	GUEAN004	Analia		Guevara	1988-04-30	leylabrophy1@gmail.com	725-259-9165	1	2025-08-02 11:18:35.77135	2025-08-02 11:18:35.77135	female
64	GUTGI001	Gilberto		Gutierrez Nochebuena	1998-10-07		725-212-9872	1	2025-08-02 11:18:36.350234	2025-08-02 11:18:36.350234	male
65	GUTDU000	Dulce	Maria	Gutierrez-Amaro	1993-11-24	Dgutierrez0624@gmail.com	702-588-0469	1	2025-08-02 11:18:36.732369	2025-08-02 11:18:36.732369	female
66	 HAHE000	Heaven		Hafen	2008-11-19	elyssafranco_16@gmail.com	702-761-9635	1	2025-08-02 11:18:37.130358	2025-08-02 11:18:37.130358	male
67	HALBA001	Barbara	L	Hall	1937-05-20	HB8013@gmail.com	725-296-9357	1	2025-08-02 11:18:37.556663	2025-08-02 11:18:37.556663	
68	HARPA008	Paulette		Harris	1947-10-08		702-656-1688	1	2025-08-02 11:18:37.993434	2025-08-02 11:18:37.993434	female
69	HERIB000	Ibis	de la Caridad	Heredia Roque	1965-09-25	ibisherida@yahoo.com	702-467-6337	1	2025-08-02 11:18:38.456248	2025-08-02 11:18:38.456248	female
70	HERHE004	Hector		Hernandez-Garcia	1981-07-15		702-793-6682	1	2025-08-02 11:18:38.824888	2025-08-02 11:18:38.824888	
71	HERIZ000	Izabella	Marie	Hernandez	1998-04-09	izabella.hernan@gmail.com	702-542-8116	1	2025-08-02 11:18:39.450505	2025-08-02 11:18:39.450505	female
72	HERJA023	Javier		Hernandez	2006-10-09	youngese702@gmail.com 	725-303-5778	1	2025-08-02 11:18:39.827381	2025-08-02 11:18:39.827381	male
73	HERJO040	Joseph	Alexander	Hernandez	2001-04-17	jojokuma2001@gmail.com	702-890-2739	1	2025-08-02 11:18:40.216446	2025-08-02 11:18:40.216446	male
74	HERMI021	Michael	Daniel	Hernandez	1985-10-18	michael5330hernandez@gmail.com	559-308-4189	1	2025-08-02 11:18:40.758002	2025-08-02 11:18:40.758002	male
75	HERRE004	Reyes	Baltazar	Hernandez-Reinado	1965-01-12		702-272-8683	1	2025-08-02 11:18:41.105076	2025-08-02 11:18:41.105076	male
76	HERMI019	Michelle		Herrera	1995-03-23	na	626-384-9703	1	2025-08-02 11:18:41.708963	2025-08-02 11:18:41.708963	female
77	HERRA012	Rual		Herrera	2014-12-05	blancabrrgn86@gmail.com	702-782-3195	1	2025-08-02 11:18:42.352714	2025-08-02 11:18:42.352714	male
78	VERYU002	Yurisan		Hierrezuelo-Nunez	1984-10-16	Yurisan84@icloud.com	605-655-4430	1	2025-08-02 11:18:42.811655	2025-08-02 11:18:42.811655	female
79	HO CA000	Cally		Ho	1982-12-29		702-406-9199	1	2025-08-02 11:18:43.427095	2025-08-02 11:18:43.427095	
80	YINKA000	Kam	Yin	Ho	1955-05-06		626-864-6418	1	2025-08-02 11:18:44.045474	2025-08-02 11:18:44.045474	
81	HUGTW000	Twayne		Hughes	1983-03-17	Twaynehuges@yahoo.com	702-561-2594	1	2025-08-02 11:18:44.392521	2025-08-02 11:18:44.392521	female
82	IBALI001	Lianet	M	Ibarra Rivera	2003-09-10	lianetmariaibarra@gmail.com	702-883-5075	1	2025-08-02 11:18:44.808571	2025-08-02 11:18:44.808571	female
83	ESCYU000	Yurisleidy		Izquierdo-Pendas	1984-10-07	YurisleidyIzquierdos@gmail.com	702-806-6329	1	2025-08-02 11:18:45.581058	2025-08-02 11:18:45.581058	female
84	JAC S000	Shatonya		Jackson	1980-06-07	 sjackson7440@yahoo.com	502-835-9175	1	2025-08-02 11:18:46.041299	2025-08-02 11:18:46.041299	female
85	JAQAD000	Adriana		Jaquez-Garcia	1986-04-04	ajaquez64@gmail.com	702-559-7315	1	2025-08-02 11:18:46.394222	2025-08-02 11:18:46.394222	female
86	JOHBR000	Brett	Easton	Johnsen	2000-02-26	brettejohnsen@gmail.com	702-499-7186	1	2025-08-02 11:18:46.817766	2025-08-02 11:18:46.817766	male
87	JOHME002	Melanie		Johnsen	1965-08-24	mjmartinee@aol.com	702-499-7800	1	2025-08-02 11:18:47.255877	2025-08-02 11:18:47.255877	female
88	ESSDO000	Donna	Markaila	Johnson	1978-01-10	DMESSEX36@GMAIL.COM	623-337-7028	1	2025-08-02 11:18:47.654794	2025-08-02 11:18:47.654794	female
89	JONDA020	Daniel	Steven	Jones	1986-06-20	dannyboyjones198625@gmail.com 	702-336-8920	1	2025-08-02 11:18:47.96826	2025-08-02 11:18:47.96826	male
90	JONSA004	Sabrina		Jones	1970-02-18	humfieild6565@gmail.com	702-418-7475	1	2025-08-02 11:18:48.368836	2025-08-02 11:18:48.368836	female
91	KINRA001	Ray	Miyares	Kindelan	1996-05-05		347-750-9199	1	2025-08-02 11:18:48.875448	2025-08-02 11:18:48.875448	male
92	KINJA005	Jasmine	Cheyenne	King	1992-06-01	jk75027@gmail.com	702-583-2799	1	2025-08-02 11:18:49.383725	2025-08-02 11:18:49.383725	female
93	KOGLA000	Lauren		Kogelschatz	1999-03-25	laurennkogelschatz@yahoo.com	248-832-9809	1	2025-08-02 11:18:49.961777	2025-08-02 11:18:49.961777	female
94	KUY C000	Cornelius		Kuykendoll	1975-01-28	dreghost369@gmail.com 	725-200-8390	1	2025-08-02 11:18:50.485087	2025-08-02 11:18:50.485087	female
95	LEAOS000	Oscar	Adrian	Leal	1998-01-31		725-577-0699	1	2025-08-02 11:18:50.91925	2025-08-02 11:18:50.91925	male
96	LEGDE000	Dennis	Bredes	Legaspi	1980-10-20	Dennislegaspi@gmail.com	702-592-8625	1	2025-08-02 11:18:51.25693	2025-08-02 11:18:51.25693	male
97	LEGJA000	Jayden		Legget	2004-10-06	Wirebo9@gmail.com	415-524-9570	1	2025-08-02 11:18:51.662868	2025-08-02 11:18:51.662868	male
98	HERAL035	Allan	Gabriel	Linarez Hernandez	1992-09-05		704-593-9378	1	2025-08-02 11:18:52.033387	2025-08-02 11:18:52.033387	male
99	LOPLU011	Luis	Daniel	Lopez Cedre	1989-06-07	daniela.adonis1989@gmail.com	786-760-5694	1	2025-08-02 11:18:52.425735	2025-08-02 11:18:52.425735	male
100	LOZFL000	Florentina		Lozeno Anorbe	1982-12-04	leydic00@gmail.com	702-684-3351	1	2025-08-02 11:18:52.822051	2025-08-02 11:18:52.822051	female
101	LUEDA001	Danny		Luevano	2001-06-15	noemymiranda@myyahoo.com	702-416-3592	1	2025-08-02 11:18:53.17065	2025-08-02 11:18:53.17065	male
102	MATOS001	Osniel		Macia Santos	1996-11-01		702-963-2009	1	2025-08-02 11:18:53.590028	2025-08-02 11:18:53.590028	male
103	MANGU001	Guadalupe		Mandujano	1995-02-03	lupemandujano2395@gmail.com	702-917-7019	1	2025-08-02 11:18:54.27235	2025-08-02 11:18:54.27235	female
104	MANWI000	Wilmer	Orlando	Manjarrez	1986-03-22	wmanjarrez0322@hotmail.com	702-888-0894	1	2025-08-02 11:18:54.627666	2025-08-02 11:18:54.627666	male
105	MARJO074	Jose	Alfonso	Mariscal	1992-07-08	JacobMariscal86@gmail.com	702-824-0933	1	2025-08-02 11:18:55.141006	2025-08-02 11:18:55.141006	male
106	ABRRA002	Raimond		Martin Abreu	1994-05-26	rc808305@gmail.com	308-267-6699	1	2025-08-02 11:18:55.52329	2025-08-02 11:18:55.52329	male
107	MARBR002	Brandon	Marshall	Martin	1994-03-21		775-209-2511	1	2025-08-02 11:18:55.89816	2025-08-02 11:18:55.89816	male
108	MARFE004	Fernando		Martinez Castellano	1980-11-02		702-986-9087	1	2025-08-02 11:18:56.300833	2025-08-02 11:18:56.300833	male
109	MARJO078	Jose		Martinez Cruz	1968-11-29		702-929-0926	1	2025-08-02 11:18:56.807619	2025-08-02 11:18:56.807619	male
110	MARWA000	Walter		Martinez-Henriquez	1969-04-02	WLTR.MRTNZ@gmail.com	702-683-6477	1	2025-08-02 11:18:57.330022	2025-08-02 11:18:57.330022	male
111	MARAN050	Anton		Martirosyan	1990-05-08		702-606-1773	1	2025-08-02 11:18:57.730394	2025-08-02 11:18:57.730394	male
112	MATMI001	Miguel	Angel-Landeros	Mata	2001-04-18		702-793-5595	1	2025-08-02 11:18:58.300107	2025-08-02 11:18:58.300107	male
113	MEDJO006	Jose		Medina	1965-12-12	jam.65@live.com	702-487-2533	1	2025-08-02 11:18:58.60708	2025-08-02 11:18:58.60708	
114	MONDA003	Daniel		Montes	1970-04-16	angeldxm@yahoo.com	702-937-0391	1	2025-08-02 11:18:59.130314	2025-08-02 11:18:59.130314	male
115	MORKA012	Karina		Morejon Palacio	1985-03-07	morejonK51@gmail.com	702-493-3755	1	2025-08-02 11:18:59.619811	2025-08-02 11:18:59.619811	female
116	MORJE007	Jesus		Moreno	1990-12-05	Jesus.Moreno05@gmail.com	702-986-4155	1	2025-08-02 11:19:00.001847	2025-08-02 11:19:00.001847	male
117	NELFA000	Failelei		Nelison	1966-10-31	iaulualofailelei@yahoo.com	808-723-0521	1	2025-08-02 11:19:00.412488	2025-08-02 11:19:00.412488	female
118	NOLCH001	Cristhian		Nolazco Linares	2006-05-20	cristhiannolazco881@gmail.com	725-577-3201	1	2025-08-02 11:19:00.924984	2025-08-02 11:19:00.924984	male
119	ODUYU000	Yunieski		Oduardo Almeida	1990-07-04	Yunieskioduardo@gmail.com	602-662-0894	1	2025-08-02 11:19:01.27171	2025-08-02 11:19:01.27171	male
120	ORTGA001	Gabrielle	Idalys	Ortiz	2004-10-23	gabrielleortiz1023@gmail.com	702-917-5921	1	2025-08-02 11:19:01.6871	2025-08-02 11:19:01.6871	female
121	OSOSA001	Samuel De Jesus		Osorio Gomez	1998-06-23		702-572-0100	1	2025-08-02 11:19:02.133095	2025-08-02 11:19:02.133095	male
122	PADOS000	Oscar	Ulises	Padilla Ochoa	1989-11-02	Oupadilla@gmail.com	360-589-0384	1	2025-08-02 11:19:02.561319	2025-08-02 11:19:02.561319	male
123	PALMA006	Maria	Del Milagro	Palomino	1977-10-21		702-513-3272	1	2025-08-02 11:19:02.976806	2025-08-02 11:19:02.976806	female
124	PARDA012	Daniel		Pardo	1994-08-03		702-846-8247	1	2025-08-02 11:19:03.33712	2025-08-02 11:19:03.33712	male
125	PADED000	Edwing	A	Paredes Yanez	1998-11-19	romman642@gmail.com	702-881-3810	1	2025-08-02 11:19:03.821934	2025-08-02 11:19:03.821934	male
126	PARJA013	Jaclene		Parker	1984-09-07	jnikole97@icloud.com	702-818-7566	1	2025-08-02 11:19:04.374804	2025-08-02 11:19:04.374804	female
127	PARCO002	Cody		Parkerson	1987-11-19		702-588-4549	1	2025-08-02 11:19:04.722543	2025-08-02 11:19:04.722543	male
128	PAUKE000	Kevin	Martin	Paulsen	1975-04-03	 spikep2004@yahoo.com	702-858-5192	1	2025-08-02 11:19:05.312263	2025-08-02 11:19:05.312263	male
129	PERLU010	Luis		Peralta	1982-06-26	mr.detaillvnv@gmail.com	702-986-8216	1	2025-08-02 11:19:05.685508	2025-08-02 11:19:05.685508	male
130	NUNHU001	Humberto	Maikel	Perez Nuniez	1979-01-24	pereznuinez790124@gmail.com	702-465-1008	1	2025-08-02 11:19:06.058134	2025-08-02 11:19:06.058134	male
131	PERER011	Ernesto		Perez	1963-08-29		702-860-7743	1	2025-08-02 11:19:06.446955	2025-08-02 11:19:06.446955	male
132	QUARO002	Robert		Quabner	1967-01-23	RSANTOS3812@YAHOO.COM	702-401-3019	1	2025-08-02 11:19:07.050373	2025-08-02 11:19:07.050373	male
133	LEYAB001	Abelardo		Quiala Leyva	1993-06-24	Aborosa11099@gmail.com	702-204-5039	1	2025-08-02 11:19:07.427718	2025-08-02 11:19:07.427718	male
134	RAMAD003	Adonis	L	Ramos Conejo	2002-03-19	ADONISCOR02@GMAIL.COM	702-559-5533	1	2025-08-02 11:19:07.75969	2025-08-02 11:19:07.75969	male
135	RAMJA011	Jaret	Pascual	Ramos	2002-11-10		702-695-9260	1	2025-08-02 11:19:08.456558	2025-08-02 11:19:08.456558	
136	RECMA001	Maura	Esther	Recinos-Martinez	1966-02-13		702-561-2344	1	2025-08-02 11:19:09.142719	2025-08-02 11:19:09.142719	female
137	REYKE001	Kelly		Reyes	1977-04-02		702-205-6325	1	2025-08-02 11:19:09.488236	2025-08-02 11:19:09.488236	female
138	REYAN010	Ana	Lorena	Reyes-Siordia	1969-10-26	anareyes36@ymail.com	702-955-0093	1	2025-08-02 11:19:09.804849	2025-08-02 11:19:09.804849	female
139	MARFR008	Frank	Reynaldo	Reyman-Ramirez	1993-08-28	FrankReynaldoReyman@gmail.com	702-210-2225	1	2025-08-02 11:19:10.170056	2025-08-02 11:19:10.170056	male
140	RIVNI001	Nikolas		Rivas	2007-03-29	admin@staircarelv.com	702-241-9462	1	2025-08-02 11:19:10.562089	2025-08-02 11:19:10.562089	male
141	RIVIN000	Ingrid		Rivera	1999-11-15		725-265-2508	1	2025-08-02 11:19:11.101503	2025-08-02 11:19:11.101503	female
142	ROBEU000	Eugene		Robichaud	1954-01-28		702-256-7678	1	2025-08-02 11:19:11.749743	2025-08-02 11:19:11.749743	male
143	RODAL033	Alain		Rodriguez Gomez	1983-11-02		702-416-5826	1	2025-08-02 11:19:12.102563	2025-08-02 11:19:12.102563	male
144	RODMI010	Migdael		Rodriguez Millar	1975-02-18	Migdael2012@gmail.com	702-969-2688	1	2025-08-02 11:19:12.579009	2025-08-02 11:19:12.579009	male
145	RODRO014	Rosalia		Rodriguez	1993-04-11		702-675-2923	1	2025-08-02 11:19:13.038188	2025-08-02 11:19:13.038188	female
146	RODYN001	Yandry		Rodriguez	1994-08-30		725-310-3594	1	2025-08-02 11:19:13.507313	2025-08-02 11:19:13.507313	male
147	ROLPA000	Paul	Arthur	Rolin	1936-01-29	eprolin@cox.net	724-503-7246	1	2025-08-02 11:19:14.002765	2025-08-02 11:19:14.002765	male
148	ROSDO009	Donna		Rosadino	1988-09-20	donna.rosadino@gmail.com	702-338-0652	1	2025-08-02 11:19:14.464274	2025-08-02 11:19:14.464274	female
149	VALEL006	Elias		Rosales-Balseca	1986-02-04		702-481-5189	1	2025-08-02 11:19:14.819549	2025-08-02 11:19:14.819549	male
150	RUSKI000	Kirk	Paul	Rustman	1969-06-22	hhspash@gmail.com	702-271-8465	1	2025-08-02 11:19:15.268095	2025-08-02 11:19:15.268095	male
151	RYAJE004	Jennifer		Ryan Koenig	1971-08-07	jennryan6196@yahoo.com	702-423-0502	1	2025-08-02 11:19:15.624574	2025-08-02 11:19:15.624574	female
152	SALLY000	Lynn	Lavell	Saltmarch	1965-11-22	lynnlynntwo@gmail.com	424-558-1718	1	2025-08-02 11:19:16.183223	2025-08-02 11:19:16.183223	male
153	SANES001	Esthepany		Sanchez Castillo	2000-10-16	Castilloesthepany@gmail.com	702-513-1757	1	2025-08-02 11:19:16.755806	2025-08-02 11:19:16.755806	female
154	SANMA039	Maria		Sanchez	1985-06-14		831-444-5917	1	2025-08-02 11:19:17.209867	2025-08-02 11:19:17.209867	
155	HAGMA001	Marcelo	J	Sandoval Pinto	1983-11-24	 SANPINTO1983@gmail.com	702-861-3838	1	2025-08-02 11:19:17.62061	2025-08-02 11:19:17.62061	male
156	SHAKO000	Koretta	Shauneke	Sharp	1983-01-20	korettas@gmail.com	702-619-4869	1	2025-08-02 11:19:18.130056	2025-08-02 11:19:18.130056	female
157	SHEGR000	Mark	Aaron	Sheppard	1968-11-28	Mark.a.sheppard@gmail.com	909-528-5943	1	2025-08-02 11:19:18.555975	2025-08-02 11:19:18.555975	male
158	SLACH002	Chandra	Arlene	Slack	1970-07-04	Chandralovespink@yahoo.com	775-537-5219	1	2025-08-02 11:19:18.915358	2025-08-02 11:19:18.915358	female
159	SMILA017	Mizelle	Larry	Smith	1982-06-11	tookah1876@gmail.com	213-662-9173	1	2025-08-02 11:19:19.386498	2025-08-02 11:19:19.386498	male
160	SOLCR005	Crystal		Solis	1997-03-15	scrystal12345@gmail.com	702-445-5355	1	2025-08-02 11:19:19.771843	2025-08-02 11:19:19.771843	female
161	SOTPE000	Peter		Sottile	1951-12-10	peterdk7@yahoo.com	702-600-9275	1	2025-08-02 11:19:20.212155	2025-08-02 11:19:20.212155	male
162	STAJO014	Joseph	Richard	Stalis	1971-10-06	jstalis@yahoo.com	650-302-4277	1	2025-08-02 11:19:20.730893	2025-08-02 11:19:20.730893	male
163	STAZA002	Zachary	Phillip	Starr	2000-12-22	Zacharypstarr@gmail.com	619-942-9286	1	2025-08-02 11:19:21.150553	2025-08-02 11:19:21.150553	male
164	STECA008	Cassidy		Steward	1994-09-01	cassidysteward@gmail.com	702-664-9883	1	2025-08-02 11:19:21.65519	2025-08-02 11:19:21.65519	female
165	STUCH003	Christopher		Studeman	1984-10-13	csfisheries@yahoo.com 	541-361-0141	1	2025-08-02 11:19:22.110624	2025-08-02 11:19:22.110624	male
166	SUZWU000	Wuenner	Zohar	Suarez Alvarez	1998-06-18	wennersuarez15@gmail.com	702-960-3032	1	2025-08-02 11:19:22.504846	2025-08-02 11:19:22.504846	male
167	TAYCH005	Chrystal		Taylor	1978-09-09	taylor.chrystal78@yahoo.com 	702-205-4866	1	2025-08-02 11:19:23.000979	2025-08-02 11:19:23.000979	female
168	TAYME002	Meagan		Taylor	1985-08-11		505-716-3890	1	2025-08-02 11:19:23.398046	2025-08-02 11:19:23.398046	female
169	TEDRY000	Ryan	Neal	Tedwell	1982-05-02	LACIC-TIDWELL@YAHOO.COM	702-499-6001	1	2025-08-02 11:19:23.776472	2025-08-02 11:19:23.776472	male
170	TORSE001	Selena	Glori	Torres	2003-11-19	selena.torres1119@gmail.com	425-953-0910	1	2025-08-02 11:19:24.175321	2025-08-02 11:19:24.175321	female
171	TRICO000	Connie		Trinh	2003-05-08	Connietrinh88@gmail.com	714-334-3785	1	2025-08-02 11:19:24.545305	2025-08-02 11:19:24.545305	female
172	ESPHE002	Heder		Ulabarri Menese	1999-10-14		716-579-9349	1	2025-08-02 11:19:24.9122	2025-08-02 11:19:24.9122	male
173	VALMO001	Moses	Martin	Valdez	1996-03-01		702-686-3631	1	2025-08-02 11:19:25.295205	2025-08-02 11:19:25.295205	male
174	VALAN015	Anabel		Valdovinos	1980-11-23		725-300-1073	1	2025-08-02 11:19:25.689015	2025-08-02 11:19:25.689015	female
175	VAZDA003	David	Lee	Vasquez	1997-10-19	davidlegits12345@gmail.com	725-207-6940	1	2025-08-02 11:19:26.093422	2025-08-02 11:19:26.093422	male
176	VASLI001	Liliana		Vazquez Morras	1988-06-03		702-542-7115	1	2025-08-02 11:19:26.541726	2025-08-02 11:19:26.541726	female
177	VERAN002	Antoin		Vercher	1964-11-02		562-241-4314	1	2025-08-02 11:19:26.948102	2025-08-02 11:19:26.948102	male
178	??0EV000	Eva		Villalobos De Padilla	1966-10-07		702-793-3763	1	2025-08-02 11:19:27.30516	2025-08-02 11:19:27.30516	female
179	WALJE005	Jerome		Walton	1980-10-12	smo_6_ke@hotmail.com	305-527-1257	1	2025-08-02 11:19:27.717906	2025-08-02 11:19:27.717906	male
180	WATDE004	Debra	A	Waters	1952-09-16	dwaters98@yahoo.com	702-301-2229	1	2025-08-02 11:19:28.143601	2025-08-02 11:19:28.143601	female
181	WATMA005	Marquis	Dijon	Watkins	1993-09-23		626-612-9456	1	2025-08-02 11:19:28.490417	2025-08-02 11:19:28.490417	male
182	WHEJO002	Joseph		Whetstine	1964-03-22	whetstine52@msn.com	775-253-9187	1	2025-08-02 11:19:28.897482	2025-08-02 11:19:28.897482	male
183	WHIDE004	Derek		White	1995-04-12	delliotwhite@gmail.com	702-985-6199	1	2025-08-02 11:19:29.247299	2025-08-02 11:19:29.247299	male
184	WOLRA002	Raymond		Wolthers	1978-07-08	lovemywife@live.com	702-325-7816	1	2025-08-02 11:19:29.638216	2025-08-02 11:19:29.638216	male
185	YAMWO000	Worawit		Yamkoksoung	1949-12-22	Petersirithai@yahoo.com	702-277-1203	1	2025-08-02 11:19:30.048275	2025-08-02 11:19:30.048275	male
186	YOUCH006	Charlton	Earl	Young	1967-11-30	eyoung11670gmailicom	702-517-4614	1	2025-08-02 11:19:30.413855	2025-08-02 11:19:30.413855	male
187	ZAVJO003	Joanna		Zavala	1987-08-04		702-929-1743	1	2025-08-02 11:19:30.866379	2025-08-02 11:19:30.866379	female
188	ZOGMI001	Michele	Lisa	Zogg	1967-09-23	michelezogg@yahoo.com	951-231-3119	1	2025-08-02 11:19:31.213841	2025-08-02 11:19:31.213841	female
189	ORTGA001	Gabrielle  Idalys		Ortiz	2004-10-23		702-917-5921	1	2025-08-02 13:49:48.023431	2025-08-02 13:49:48.023431	
190	YINKA000	Kam Yin		Ho	1955-05-06		626-864-6418	1	2025-08-02 13:49:48.48449	2025-08-02 13:49:48.48449	
191	JOHBR000	Brett Easton		Johnsen	2000-02-26		702-499-7186	1	2025-08-02 13:49:53.002975	2025-08-02 13:49:53.002975	
192	HAGMA001	Marcelo J		Sandoval Pinto	1983-11-24		702-861-3838	1	2025-08-02 13:49:54.658236	2025-08-02 13:49:54.658236	
193	RAMJA011	Jaret  Pascual		Ramos	2002-11-10		702-695-9260	1	2025-08-02 13:49:55.162739	2025-08-02 13:49:55.162739	
194	WATDE004	Debra A		Waters	1952-09-16		702-301-2229	1	2025-08-02 13:49:56.202653	2025-08-02 13:49:56.202653	
195	CUEDA000	David Nelson Marck Anthony		Cueva-Llanos	1990-02-12		702-415-0423	1	2025-08-02 13:49:56.611331	2025-08-02 13:49:56.611331	
196	MARBR002	Brandon Marshall		Martin	1994-03-21		775-209-2511	1	2025-08-02 13:49:57.231361	2025-08-02 13:49:57.231361	
197	KINJA005	Jasmine Cheyenne		King	1992-06-01		702-583-2799	1	2025-08-02 13:49:57.451555	2025-08-02 13:49:57.451555	
198	COMRO000	Ross  M		Conway	1981-08-26		702-481-0092	1	2025-08-02 13:49:58.013882	2025-08-02 13:49:58.013882	
199	HALBA001	Barbara L		Hall	1937-05-20		725-296-9357	1	2025-08-02 13:49:58.342915	2025-08-02 13:49:58.342915	
200	REYAN010	Ana Lorena		Reyes-Siordia	1969-10-26		702-955-0093	1	2025-08-02 13:49:58.559255	2025-08-02 13:49:58.559255	
201	BROAM005	Amanda Rose		Brown	1995-03-17		909-913-9466	1	2025-08-02 13:49:59.421209	2025-08-02 13:49:59.421209	
202	PAUKE000	Kevin Martin		Paulsen	1975-04-03		702-858-5192	1	2025-08-02 13:49:59.644834	2025-08-02 13:49:59.644834	
203	HERIZ000	Izabella Marie		Hernandez	1998-04-09		702-542-8116	1	2025-08-02 13:50:00.065121	2025-08-02 13:50:00.065121	
204	RECMA001	Maura Esther		Recinos-Martinez	1966-02-13		702-561-2344	1	2025-08-02 13:50:00.347014	2025-08-02 13:50:00.347014	
205	HAHE000	Heaven		Hafen	2008-11-19		702-761-9635	1	2025-08-02 13:50:00.810706	2025-08-02 13:50:00.810706	
206	WATMA005	Marquis Dijon		Watkins	1993-09-23		626-612-9456	1	2025-08-02 13:50:01.022249	2025-08-02 13:50:01.022249	
207	MANWI000	Wilmer Orlando		Manjarrez	1986-03-22		702-888-0894	1	2025-08-02 13:50:01.649758	2025-08-02 13:50:01.649758	
208	MARFR008	Frank Reynaldo		Reyman-Ramirez	1993-08-28		702-210-2225	1	2025-08-02 13:50:02.94189	2025-08-02 13:50:02.94189	
209	MARJO074	Jose Alfonso		Mariscal	1992-07-08		702-824-0933	1	2025-08-02 13:50:03.744943	2025-08-02 13:50:03.744943	
210	FOLBE000	Burton Alan		Folkart	1961-01-11		702-955-5252ext521	1	2025-08-02 13:50:04.501926	2025-08-02 13:50:04.501926	
211	GUTDU000	Dulce Maria		Gutierrez-Amaro	1993-11-24		702-588-0469	1	2025-08-02 13:50:05.052674	2025-08-02 13:50:05.052674	
212	HERMI021	Michael Daniel		Hernandez	1985-10-18		559-308-4189	1	2025-08-02 13:50:05.269888	2025-08-02 13:50:05.269888	
213	HERRE004	Reyes Baltazar		Hernandez-Reinado	1965-01-12		702-272-8683	1	2025-08-02 13:50:05.882271	2025-08-02 13:50:05.882271	
214	??0MI000	Miriam Zamira		Flores Cabrera	2005-01-27		702-809-2152	1	2025-08-02 13:50:06.338306	2025-08-02 13:50:06.338306	
215	VAZDA003	David Lee		Vasquez	1997-10-19		725-207-6940	1	2025-08-02 13:50:07.490252	2025-08-02 13:50:07.490252	
216	LEAOS000	Oscar Adrian		Leal	1998-01-31		725-577-0699	1	2025-08-02 13:50:07.816941	2025-08-02 13:50:07.816941	
217	ALVMA024	Maria Lourdes		Alvarez	1968-02-19		702-640-9566	1	2025-08-02 13:50:08.336988	2025-08-02 13:50:08.336988	
218	BRILA001	Lazaro O		Brizuela Gonzalez	1995-11-03		702-741-3771	1	2025-08-02 13:50:08.630844	2025-08-02 13:50:08.630844	
219	NUNHU001	Humberto  Maikel		Perez Nuniez	1979-01-24		702-465-1008	1	2025-08-02 13:50:08.933476	2025-08-02 13:50:08.933476	
220	CORJU009	Juan Carlos		Corona Gonzalez	1989-06-09		702-786-5255	1	2025-08-02 13:50:09.873238	2025-08-02 13:50:09.873238	
221	LOPLU011	Luis Daniel		Lopez Cedre	1989-06-07		786-760-5694	1	2025-08-02 13:50:10.492665	2025-08-02 13:50:10.492665	
222	BOLGL000	Gloria Angelicia		Bolanos	1953-08-01		702-561-7422	1	2025-08-02 13:50:11.415633	2025-08-02 13:50:11.415633	
223	SALLY000	Lynn Lavell		Saltmarch	1965-11-22		424-558-1718	1	2025-08-02 13:50:12.139981	2025-08-02 13:50:12.139981	
224	PADED000	Edwing A		Paredes Yanez	1998-11-19		702-881-3810	1	2025-08-02 13:50:12.511725	2025-08-02 13:50:12.511725	
225	HERIB000	Ibis de la Caridad		Heredia Roque	1965-09-25		702-467-6337	1	2025-08-02 13:50:12.885223	2025-08-02 13:50:12.885223	
226	HERAL035	Allan Gabriel		Linarez Hernandez	1992-09-05		704-593-9378	1	2025-08-02 13:50:13.507697	2025-08-02 13:50:13.507697	
227	COSMI002	Miguel  Alejandro		Gomez Costa	1996-12-30		305-391-0038	1	2025-08-02 13:50:13.725484	2025-08-02 13:50:13.725484	
228	TORSE001	Selena  Glori		Torres	2003-11-19		425-953-0910	1	2025-08-02 13:50:14.05754	2025-08-02 13:50:14.05754	
229	SUZWU000	Wuenner  Zohar		Suarez Alvarez	1998-06-18		702-960-3032	1	2025-08-02 13:50:14.374155	2025-08-02 13:50:14.374155	
230	JAIJH000	Jhon  Jairo		Chalares Arboleda	1987-04-02		747-245-9148	1	2025-08-02 13:50:14.590857	2025-08-02 13:50:14.590857	
231	RAMAD003	Adonis  L		Ramos Conejo	2002-03-19		702-559-5533	1	2025-08-02 13:50:14.934141	2025-08-02 13:50:14.934141	
232	SHAKO000	Koretta  Shauneke		Sharp	1983-01-20		702-619-4869	1	2025-08-02 13:50:15.506042	2025-08-02 13:50:15.506042	
233	CANIV000	Ivonne Kassandra		Candelario Diaz	1998-08-17		702-238-6784	1	2025-08-02 13:50:15.933246	2025-08-02 13:50:15.933246	
234	ALVJO014	Jose Arturo		Alvarez	2007-02-14		702-875-3283	1	2025-08-02 13:50:16.591939	2025-08-02 13:50:16.591939	
235	SMILA017	Mizelle Larry		Smith	1982-06-11		213-662-9173	1	2025-08-02 13:50:17.054295	2025-08-02 13:50:17.054295	
236	YOUCH006	Charlton  Earl		Young	1967-11-30		702-517-4614	1	2025-08-02 13:50:17.354711	2025-08-02 13:50:17.354711	
237	PADOS000	Oscar Ulises		Padilla Ochoa	1989-11-02		360-589-0384	1	2025-08-02 13:50:17.713404	2025-08-02 13:50:17.713404	
238	LEGDE000	Dennis Bredes		Legaspi	1980-10-20		702-592-8625	1	2025-08-02 13:50:18.316083	2025-08-02 13:50:18.316083	
239	DINJU000	Juliana Tuong VI		Dinh	2001-02-16		702-372-3230	1	2025-08-02 13:50:18.868805	2025-08-02 13:50:18.868805	
240	KINRA001	Ray Miyares		Kindelan	1996-05-05		347-750-9199	1	2025-08-02 13:50:19.21141	2025-08-02 13:50:19.21141	
241	STAJO014	Joseph Richard		Stalis	1971-10-06		650-302-4277	1	2025-08-02 13:50:19.578982	2025-08-02 13:50:19.578982	
242	BASWE000	Wendy Carolina		Basto	1987-04-01		702-477-5419	1	2025-08-02 13:50:19.79976	2025-08-02 13:50:19.79976	
243	MATMI001	Miguel Angel-Landeros		Mata	2001-04-18		702-793-5595	1	2025-08-02 13:50:20.54519	2025-08-02 13:50:20.54519	
244	MUNER002	Erick Alejandro		Camey-Munoz	1988-06-04		702-858-4131	1	2025-08-02 13:50:20.763043	2025-08-02 13:50:20.763043	
245	DAVTE002	Teresita De Jesus		Davidson	1964-04-27		702-762-6770	1	2025-08-02 13:50:21.688132	2025-08-02 13:50:21.688132	
246	AMAJU003	Juan C Tomax		Amaxtal	1995-11-05		702-826-9633	1	2025-08-02 13:50:22.719502	2025-08-02 13:50:22.719502	
247	IBALI001	Lianet M		Ibarra Rivera	2003-09-10		702-883-5075	1	2025-08-02 13:50:23.665126	2025-08-02 13:50:23.665126	
248	CARGL002	Gloria Miriam		Cardoza-Huezo	1979-10-31		818-335-6442	1	2025-08-02 13:50:23.881252	2025-08-02 13:50:23.881252	
249	JONDA020	Daniel Steven		Jones	1986-06-20		702-336-8920	1	2025-08-02 13:50:24.100166	2025-08-02 13:50:24.100166	
250	ESCEM001	Emma Evelyne		Escamilla	2007-01-03		702-289-7368	1	2025-08-02 13:50:24.524149	2025-08-02 13:50:24.524149	
\.


--
-- TOC entry 4940 (class 0 OID 90791)
-- Dependencies: 229
-- Data for Name: providers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.providers (id, name, status, created_at, updated_at) FROM stdin;
1	Dr. Anthony Ponce De Leon	1	2025-08-03 21:27:59.18563	2025-08-03 21:27:59.185636
2	Align Med	1	2025-08-03 21:28:00.385295	2025-08-03 21:28:00.385303
3	Dr. Renée Gladstone	1	2025-08-03 21:28:01.238625	2025-08-03 21:28:01.238631
4	Dr. Heath Crawford	1	2025-08-03 21:28:01.719633	2025-08-03 21:28:01.719638
5	Lesley Vance	1	2025-08-03 21:28:02.559812	2025-08-03 21:28:02.559819
6	Dr. Jordan Lea	1	2025-08-03 21:28:04.139924	2025-08-03 21:28:04.13993
7	Michael Digregorio M.D.	1	2025-08-03 21:28:04.655887	2025-08-03 21:28:04.655893
8	Bret Brown	1	2025-08-03 21:28:08.106211	2025-08-03 21:28:08.106221
9	Dr. Timothy McCauley	1	2025-08-03 21:28:10.62574	2025-08-03 21:28:10.625746
10	Dr. Eric Sabol	1	2025-08-03 21:28:11.472954	2025-08-03 21:28:11.472961
11	Delfina Simpson APRN	1	2025-08-03 21:28:12.465131	2025-08-03 21:28:12.465138
12	Michael Epperson	1	2025-08-03 21:28:13.076858	2025-08-03 21:28:13.076865
13	Dr. Christian Quintero	1	2025-08-03 21:28:16.151997	2025-08-03 21:28:16.152005
14	Dr. Edmund Pasimio MD	1	2025-08-03 21:28:17.317347	2025-08-03 21:28:17.317351
15	Dr. Nicholas Burnett	1	2025-08-03 21:28:23.647271	2025-08-03 21:28:23.647278
16	Marigold Grino	1	2025-08-03 21:28:24.15802	2025-08-03 21:28:24.158027
17	Dr. Jessica McKelvey	1	2025-08-03 21:28:24.667495	2025-08-03 21:28:24.667501
18	Dr. Adam Poole	1	2025-08-03 21:28:29.435727	2025-08-03 21:28:29.435733
19	Dr. Chris Kim	1	2025-08-03 21:29:09.441269	2025-08-03 21:29:09.441278
20	Rafael Callanta NP	1	2025-08-03 21:29:10.137072	2025-08-03 21:29:10.137083
21	Stephen Alexander	1	2025-08-03 21:29:10.900561	2025-08-03 21:29:10.900572
22	Dillan Van Ness	1	2025-08-03 21:29:23.85713	2025-08-03 21:29:23.85715
23	Dr. Bianca Flury	1	2025-08-03 21:30:18.95415	2025-08-03 21:30:18.954163
24	Todd Gardner	1	2025-08-03 21:30:21.540749	2025-08-03 21:30:21.540757
\.


--
-- TOC entry 4942 (class 0 OID 90796)
-- Dependencies: 231
-- Data for Name: refresh_tokens; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.refresh_tokens (id, user_id, token, expires_at, created_at) FROM stdin;
1	1	eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOjEsImlhdCI6MTc1NDMxOTY4NywiZXhwIjoxNzU0OTI0NDg3fQ.lRvUmnbEowOSU6vXDbLMRyNVaGEMHOT_fV9j7MUJ99U	2025-08-11 08:01:27.736-07	2025-08-04 08:01:27.736894-07
\.


--
-- TOC entry 4944 (class 0 OID 90801)
-- Dependencies: 233
-- Data for Name: rule_attorneys_mapping; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.rule_attorneys_mapping (id, rule_id, attorney_id, created_at, updated_at) FROM stdin;
\.


--
-- TOC entry 4946 (class 0 OID 90807)
-- Dependencies: 235
-- Data for Name: rules; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.rules (id, provider_id, bonus_percentage, status, created_at, updated_at, rule_name) FROM stdin;
\.


--
-- TOC entry 4948 (class 0 OID 90813)
-- Dependencies: 237
-- Data for Name: settlements; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.settlements (id, patient_id, attorney_id, settlement_date, total_billed_charges, status, created_at, updated_at, settlement_percentage, settlement_amount) FROM stdin;
1	\N	77	2024-01-02	7835.00	1	2025-08-03 19:53:58.790287	2025-08-03 19:53:58.790287	0.55	4309.25
2	\N	57	2024-02-13	612.20	1	2025-08-03 19:53:58.972095	2025-08-03 19:53:58.972095	0.82	505.00
3	\N	78	2024-04-08	11165.00	1	2025-08-03 19:53:59.400745	2025-08-03 19:53:59.400745	0.50	5582.50
4	\N	79	2024-04-15	9420.00	1	2025-08-03 19:53:59.788342	2025-08-03 19:53:59.788342	0.44	4170.00
5	\N	80	2024-04-15	11510.00	1	2025-08-03 19:54:00.147986	2025-08-03 19:54:00.147986	0.50	5755.00
6	\N	80	2024-04-23	2995.00	1	2025-08-03 19:54:00.461438	2025-08-03 19:54:00.461438	0.35	1048.25
7	\N	81	2024-04-30	12760.00	1	2025-08-03 19:54:00.872818	2025-08-03 19:54:00.872818	0.50	6380.00
8	\N	51	2024-04-30	2245.00	1	2025-08-03 19:54:01.052733	2025-08-03 19:54:01.052733	0.35	785.75
9	\N	80	2024-05-01	5885.00	1	2025-08-03 19:54:01.281953	2025-08-03 19:54:01.281953	0.45	2648.25
10	\N	80	2024-05-02	1195.00	1	2025-08-03 19:54:01.52789	2025-08-03 19:54:01.52789	0.45	537.75
11	\N	80	2024-05-03	1365.00	1	2025-08-03 19:54:01.781028	2025-08-03 19:54:01.781028	0.45	614.25
12	\N	80	2024-05-07	500.00	1	2025-08-03 19:54:02.009262	2025-08-03 19:54:02.009262	0.55	275.00
13	\N	82	2024-05-14	12285.00	1	2025-08-03 19:54:02.426034	2025-08-03 19:54:02.426034	0.48	5890.00
14	\N	83	2024-05-15	760.00	1	2025-08-03 19:54:02.857571	2025-08-03 19:54:02.857571	0.50	380.00
15	\N	84	2024-05-21	8855.00	1	2025-08-03 19:54:03.374414	2025-08-03 19:54:03.374414	0.71	6250.00
16	\N	80	2024-05-23	500.00	1	2025-08-03 19:54:03.709054	2025-08-03 19:54:03.709054	0.60	300.00
17	\N	85	2024-05-28	7980.00	1	2025-08-03 19:54:04.723445	2025-08-03 19:54:04.723445	0.55	4389.00
18	\N	52	2024-05-29	8010.00	1	2025-08-03 19:54:05.078429	2025-08-03 19:54:05.078429	0.50	4005.00
19	\N	44	2024-06-03	6990.00	1	2025-08-03 19:54:05.376397	2025-08-03 19:54:05.376397	0.54	3780.00
20	\N	44	2024-06-03	3290.00	1	2025-08-03 19:54:05.87633	2025-08-03 19:54:05.87633	0.70	2303.00
21	\N	45	2024-06-03	5630.00	1	2025-08-03 19:54:06.263329	2025-08-03 19:54:06.263329	0.50	2815.00
22	\N	86	2024-06-03	1200.00	1	2025-08-03 19:54:06.882462	2025-08-03 19:54:06.882462	0.50	600.00
23	\N	87	2024-06-03	10700.00	1	2025-08-03 19:54:07.635413	2025-08-03 19:54:07.635413	0.50	5350.00
24	\N	52	2024-06-03	1810.00	1	2025-08-03 19:54:07.962495	2025-08-03 19:54:07.962495	0.60	1086.00
25	\N	60	2024-06-03	2610.00	1	2025-08-03 19:54:08.210043	2025-08-03 19:54:08.210043	0.85	2218.50
26	\N	44	2024-06-04	11360.00	1	2025-08-03 19:54:08.584555	2025-08-03 19:54:08.584555	0.53	6055.63
27	\N	44	2024-06-04	7495.00	1	2025-08-03 19:54:08.94901	2025-08-03 19:54:08.94901	0.71	5284.56
28	\N	44	2024-06-04	7685.00	1	2025-08-03 19:54:09.222596	2025-08-03 19:54:09.222596	0.44	3398.40
29	\N	88	2024-06-04	16870.00	1	2025-08-03 19:54:09.675838	2025-08-03 19:54:09.675838	0.90	15183.00
30	\N	88	2024-06-04	11300.00	1	2025-08-03 19:54:09.901918	2025-08-03 19:54:09.901918	0.67	7571.00
31	\N	80	2024-06-04	8240.00	1	2025-08-03 19:54:10.26526	2025-08-03 19:54:10.26526	0.50	4107.50
32	\N	89	2024-06-04	11655.00	1	2025-08-03 19:54:10.777811	2025-08-03 19:54:10.777811	0.34	4000.00
33	\N	90	2024-06-04	7450.00	1	2025-08-03 19:54:11.432371	2025-08-03 19:54:11.432371	0.55	4061.75
34	\N	90	2024-06-04	9390.00	1	2025-08-03 19:54:11.644178	2025-08-03 19:54:11.644178	0.53	5000.00
35	\N	91	2024-06-05	11165.00	1	2025-08-03 19:54:12.182861	2025-08-03 19:54:12.182861	0.40	4466.00
36	\N	88	2024-06-05	2290.00	1	2025-08-03 19:54:12.531467	2025-08-03 19:54:12.531467	0.26	600.00
37	\N	57	2024-06-05	1000.00	1	2025-08-03 19:54:13.000599	2025-08-03 19:54:13.000599	0.75	750.00
38	\N	60	2024-06-05	10880.00	1	2025-08-03 19:54:13.320127	2025-08-03 19:54:13.320127	0.41	4512.50
39	\N	53	2024-06-05	8780.00	1	2025-08-03 19:54:13.550302	2025-08-03 19:54:13.550302	0.57	5000.00
40	\N	44	2024-06-06	9045.00	1	2025-08-03 19:54:13.936166	2025-08-03 19:54:13.936166	0.37	3381.66
41	\N	44	2024-06-06	550.00	1	2025-08-03 19:54:14.309868	2025-08-03 19:54:14.309868	0.23	128.27
42	\N	88	2024-06-06	2795.00	1	2025-08-03 19:54:14.64764	2025-08-03 19:54:14.64764	0.75	2096.25
43	\N	88	2024-06-06	6260.00	1	2025-08-03 19:54:14.849796	2025-08-03 19:54:14.849796	0.50	3130.00
44	\N	65	2024-06-06	11715.00	1	2025-08-03 19:54:15.171449	2025-08-03 19:54:15.171449	0.60	7029.00
45	\N	44	2024-06-07	9535.00	1	2025-08-03 19:54:15.44704	2025-08-03 19:54:15.44704	0.68	6465.92
46	\N	92	2024-06-07	4255.00	1	2025-08-03 19:54:15.943422	2025-08-03 19:54:15.943422	0.60	2553.00
47	\N	92	2024-06-07	2140.00	1	2025-08-03 19:54:16.16056	2025-08-03 19:54:16.16056	0.60	1284.00
48	\N	93	2024-06-09	3615.00	1	2025-08-03 19:54:16.667677	2025-08-03 19:54:16.667677	0.65	2349.75
49	\N	43	2024-06-10	3575.00	1	2025-08-03 19:54:16.878493	2025-08-03 19:54:16.878493	0.70	2500.00
50	\N	43	2024-06-10	8400.00	1	2025-08-03 19:54:17.166976	2025-08-03 19:54:17.166976	0.50	4200.00
51	\N	43	2024-06-10	7990.00	1	2025-08-03 19:54:17.480633	2025-08-03 19:54:17.480633	0.65	5193.00
52	\N	43	2024-06-10	7790.00	1	2025-08-03 19:54:17.795274	2025-08-03 19:54:17.795274	0.65	5063.00
53	\N	43	2024-06-10	6885.00	1	2025-08-03 19:54:18.042237	2025-08-03 19:54:18.042237	0.65	4475.00
54	\N	57	2024-06-10	1675.00	1	2025-08-03 19:54:18.37936	2025-08-03 19:54:18.37936	0.50	837.50
55	\N	44	2024-06-11	8585.00	1	2025-08-03 19:54:18.744306	2025-08-03 19:54:18.744306	0.28	2437.22
56	\N	44	2024-06-11	9135.00	1	2025-08-03 19:54:19.036214	2025-08-03 19:54:19.036214	0.53	4878.83
57	\N	94	2024-06-11	10430.00	1	2025-08-03 19:54:19.520507	2025-08-03 19:54:19.520507	0.80	8324.00
58	\N	80	2024-06-11	11313.20	1	2025-08-03 19:54:19.745647	2025-08-03 19:54:19.745647	0.35	4000.00
59	\N	95	2024-06-11	12730.00	1	2025-08-03 19:54:20.236984	2025-08-03 19:54:20.236984	0.47	6000.00
60	\N	96	2024-06-12	3320.00	1	2025-08-03 19:54:20.609648	2025-08-03 19:54:20.609648	0.50	1660.00
61	\N	44	2024-06-13	6520.00	1	2025-08-03 19:54:20.860807	2025-08-03 19:54:20.860807	0.38	2500.00
62	\N	80	2024-06-13	16570.00	1	2025-08-03 19:54:21.277284	2025-08-03 19:54:21.277284	0.55	9113.50
63	\N	44	2024-06-15	6065.00	1	2025-08-03 19:54:21.552826	2025-08-03 19:54:21.552826	0.60	3639.00
64	\N	85	2024-06-15	9490.00	1	2025-08-03 19:54:21.766017	2025-08-03 19:54:21.766017	0.65	6168.50
65	\N	97	2024-06-15	850.00	1	2025-08-03 19:54:22.251936	2025-08-03 19:54:22.251936	0.70	595.00
66	\N	60	2024-06-16	4045.00	1	2025-08-03 19:54:22.455921	2025-08-03 19:54:22.455921	0.50	2022.50
67	\N	60	2024-06-16	2465.00	1	2025-08-03 19:54:22.766054	2025-08-03 19:54:22.766054	0.71	1750.50
68	\N	79	2024-06-17	14715.00	1	2025-08-03 19:54:23.041453	2025-08-03 19:54:23.041453	0.50	7357.50
69	\N	57	2024-06-17	1950.00	1	2025-08-03 19:54:23.327581	2025-08-03 19:54:23.327581	0.90	1750.00
70	\N	44	2024-06-18	6730.00	1	2025-08-03 19:54:23.615652	2025-08-03 19:54:23.615652	0.44	2941.00
71	\N	98	2024-06-18	11460.00	1	2025-08-03 19:54:24.285526	2025-08-03 19:54:24.285526	0.50	5730.00
72	\N	45	2024-06-18	5740.00	1	2025-08-03 19:54:24.498815	2025-08-03 19:54:24.498815	0.38	2200.00
73	\N	80	2024-06-18	5200.00	1	2025-08-03 19:54:24.899725	2025-08-03 19:54:24.899725	0.55	2860.00
74	\N	48	2024-06-18	7270.00	1	2025-08-03 19:54:25.148124	2025-08-03 19:54:25.148124	0.50	3602.50
75	\N	48	2024-06-18	7335.00	1	2025-08-03 19:54:25.452691	2025-08-03 19:54:25.452691	0.50	3635.00
76	\N	48	2024-06-18	10080.00	1	2025-08-03 19:54:25.730912	2025-08-03 19:54:25.730912	0.54	5436.21
77	\N	86	2024-06-18	9455.00	1	2025-08-03 19:54:26.100606	2025-08-03 19:54:26.100606	0.50	4727.50
78	\N	86	2024-06-18	2165.00	1	2025-08-03 19:54:26.349032	2025-08-03 19:54:26.349032	0.50	1082.50
79	\N	99	2024-06-18	7465.00	1	2025-08-03 19:54:27.020772	2025-08-03 19:54:27.020772	0.56	4200.00
80	\N	45	2024-06-20	6945.00	1	2025-08-03 19:54:27.273808	2025-08-03 19:54:27.273808	0.50	3472.50
81	\N	100	2024-06-20	11485.00	1	2025-08-03 19:54:27.765671	2025-08-03 19:54:27.765671	0.20	2297.00
82	\N	101	2024-06-20	4500.00	1	2025-08-03 19:54:28.286181	2025-08-03 19:54:28.286181	0.60	2700.00
83	\N	52	2024-06-20	6105.00	1	2025-08-03 19:54:28.484933	2025-08-03 19:54:28.484933	0.50	3052.50
84	\N	52	2024-06-20	2295.00	1	2025-08-03 19:54:28.817848	2025-08-03 19:54:28.817848	0.50	1147.50
85	\N	53	2024-06-20	8170.00	1	2025-08-03 19:54:29.156181	2025-08-03 19:54:29.156181	0.50	4060.00
86	\N	80	2024-06-21	3930.00	1	2025-08-03 19:54:29.404771	2025-08-03 19:54:29.404771	0.65	2554.50
87	\N	65	2024-06-21	7300.60	1	2025-08-03 19:54:29.72672	2025-08-03 19:54:29.72672	0.60	4377.00
88	\N	60	2024-06-21	7970.00	1	2025-08-03 19:54:30.037751	2025-08-03 19:54:30.037751	0.67	5339.90
89	\N	60	2024-06-21	4175.00	1	2025-08-03 19:54:30.280546	2025-08-03 19:54:30.280546	0.70	2922.50
90	\N	93	2024-06-22	4205.00	1	2025-08-03 19:54:30.594187	2025-08-03 19:54:30.594187	0.50	2102.50
91	\N	81	2024-06-24	1495.00	1	2025-08-03 19:54:30.866836	2025-08-03 19:54:30.866836	0.70	1046.50
92	145	55	2024-06-24	5150.00	1	2025-08-03 19:54:31.191653	2025-08-03 19:54:31.191653	0.45	2317.50
93	\N	102	2024-06-24	1715.00	1	2025-08-03 19:54:31.572755	2025-08-03 19:54:31.572755	0.58	1000.00
94	\N	102	2024-06-24	7805.00	1	2025-08-03 19:54:31.793984	2025-08-03 19:54:31.793984	0.53	4127.50
95	\N	57	2024-06-24	550.00	1	2025-08-03 19:54:32.144126	2025-08-03 19:54:32.144126	0.73	400.00
96	\N	53	2024-06-24	7330.00	1	2025-08-03 19:54:32.484888	2025-08-03 19:54:32.484888	0.71	5200.00
97	\N	44	2024-06-25	8685.00	1	2025-08-03 19:54:32.684042	2025-08-03 19:54:32.684042	0.64	5587.66
98	\N	44	2024-06-25	6245.00	1	2025-08-03 19:54:32.937072	2025-08-03 19:54:32.937072	0.50	3097.50
99	\N	103	2024-06-25	8290.00	1	2025-08-03 19:54:33.514149	2025-08-03 19:54:33.514149	0.60	5000.00
100	\N	94	2024-06-25	7860.00	1	2025-08-03 19:54:33.87137	2025-08-03 19:54:33.87137	0.59	4600.00
101	\N	104	2024-06-25	2025.00	1	2025-08-03 19:54:34.278449	2025-08-03 19:54:34.278449	0.52	1060.00
102	\N	55	2024-06-25	3205.00	1	2025-08-03 19:54:34.523973	2025-08-03 19:54:34.523973	0.31	1000.00
103	\N	55	2024-06-25	5795.00	1	2025-08-03 19:54:34.753829	2025-08-03 19:54:34.753829	0.50	2897.50
104	\N	44	2024-06-26	3140.00	1	2025-08-03 19:54:34.977148	2025-08-03 19:54:34.977148	0.70	2198.00
105	\N	44	2024-06-26	5385.00	1	2025-08-03 19:54:35.320327	2025-08-03 19:54:35.320327	0.57	3069.45
106	\N	44	2024-06-26	8000.00	1	2025-08-03 19:54:35.565406	2025-08-03 19:54:35.565406	0.62	4939.27
107	\N	44	2024-06-26	11440.00	1	2025-08-03 19:54:35.79685	2025-08-03 19:54:35.79685	0.51	5873.33
108	\N	44	2024-06-26	3330.00	1	2025-08-03 19:54:36.037847	2025-08-03 19:54:36.037847	0.48	1604.33
109	\N	44	2024-06-26	6660.00	1	2025-08-03 19:54:36.290612	2025-08-03 19:54:36.290612	0.45	3000.00
110	\N	105	2024-06-26	9435.00	1	2025-08-03 19:54:36.645379	2025-08-03 19:54:36.645379	0.64	6000.00
111	\N	88	2024-06-26	7300.00	1	2025-08-03 19:54:36.819333	2025-08-03 19:54:36.819333	0.54	3942.00
112	\N	83	2024-06-26	3970.00	1	2025-08-03 19:54:37.063313	2025-08-03 19:54:37.063313	0.49	1928.40
113	\N	55	2024-06-26	9535.00	1	2025-08-03 19:54:37.297901	2025-08-03 19:54:37.297901	0.50	4767.50
114	\N	52	2024-06-26	8460.00	1	2025-08-03 19:54:37.53886	2025-08-03 19:54:37.53886	0.50	4230.00
115	\N	57	2024-06-26	2930.00	1	2025-08-03 19:54:37.777625	2025-08-03 19:54:37.777625	0.52	1530.00
116	\N	53	2024-06-26	1550.00	1	2025-08-03 19:54:38.038714	2025-08-03 19:54:38.038714	0.39	600.00
117	\N	44	2024-06-27	7550.00	1	2025-08-03 19:54:38.270127	2025-08-03 19:54:38.270127	0.70	5257.00
118	\N	44	2024-06-27	8900.00	1	2025-08-03 19:54:38.496228	2025-08-03 19:54:38.496228	0.70	6230.00
119	\N	44	2024-06-27	7250.00	1	2025-08-03 19:54:38.728501	2025-08-03 19:54:38.728501	0.57	4120.00
120	\N	44	2024-06-27	10085.00	1	2025-08-03 19:54:38.955604	2025-08-03 19:54:38.955604	0.47	4734.33
121	\N	44	2024-06-27	4210.00	1	2025-08-03 19:54:39.198258	2025-08-03 19:54:39.198258	0.32	1347.00
122	\N	44	2024-06-27	7945.00	1	2025-08-03 19:54:39.428989	2025-08-03 19:54:39.428989	0.48	3829.33
123	\N	44	2024-06-27	2230.00	1	2025-08-03 19:54:39.671764	2025-08-03 19:54:39.671764	0.51	1146.66
124	\N	44	2024-06-27	5695.00	1	2025-08-03 19:54:39.923113	2025-08-03 19:54:39.923113	0.18	1000.00
125	\N	44	2024-06-27	3895.00	1	2025-08-03 19:54:40.163995	2025-08-03 19:54:40.163995	0.64	2495.00
126	\N	45	2024-06-27	6115.00	1	2025-08-03 19:54:40.390614	2025-08-03 19:54:40.390614	0.50	3057.50
127	\N	45	2024-06-27	1305.00	1	2025-08-03 19:54:40.642674	2025-08-03 19:54:40.642674	0.50	652.50
128	\N	94	2024-06-27	9985.00	1	2025-08-03 19:54:40.826746	2025-08-03 19:54:40.826746	0.60	5991.00
129	\N	89	2024-06-27	10740.00	1	2025-08-03 19:54:41.07529	2025-08-03 19:54:41.07529	0.70	7518.00
130	\N	48	2024-06-27	3610.00	1	2025-08-03 19:54:41.321635	2025-08-03 19:54:41.321635	0.65	2346.50
131	\N	52	2024-06-27	7755.00	1	2025-08-03 19:54:41.538232	2025-08-03 19:54:41.538232	0.50	3877.50
132	\N	60	2024-06-27	4375.00	1	2025-08-03 19:54:41.790535	2025-08-03 19:54:41.790535	0.65	2843.75
133	\N	44	2024-06-28	8760.00	1	2025-08-03 19:54:42.065596	2025-08-03 19:54:42.065596	0.74	6478.66
134	\N	44	2024-06-28	4295.00	1	2025-08-03 19:54:42.259454	2025-08-03 19:54:42.259454	0.70	3006.50
135	\N	44	2024-06-28	3640.00	1	2025-08-03 19:54:42.517823	2025-08-03 19:54:42.517823	0.50	1807.66
136	\N	44	2024-06-28	7045.00	1	2025-08-03 19:54:42.760987	2025-08-03 19:54:42.760987	0.66	4669.90
137	\N	44	2024-06-28	8790.00	1	2025-08-03 19:54:42.998809	2025-08-03 19:54:42.998809	0.70	6153.00
138	\N	44	2024-06-28	6215.00	1	2025-08-03 19:54:43.253398	2025-08-03 19:54:43.253398	0.50	3107.50
139	\N	60	2024-06-28	8585.00	1	2025-08-03 19:54:43.492543	2025-08-03 19:54:43.492543	0.72	6181.20
140	\N	43	2024-07-02	3780.00	1	2025-08-03 19:54:43.744146	2025-08-03 19:54:43.744146	0.70	2640.00
141	\N	44	2024-07-02	6205.00	1	2025-08-03 19:54:43.989606	2025-08-03 19:54:43.989606	0.55	3427.14
142	\N	44	2024-07-02	6905.00	1	2025-08-03 19:54:44.223431	2025-08-03 19:54:44.223431	0.69	4733.50
143	\N	44	2024-07-02	3815.00	1	2025-08-03 19:54:44.465118	2025-08-03 19:54:44.465118	0.55	2103.33
144	\N	44	2024-07-02	6690.00	1	2025-08-03 19:54:44.690208	2025-08-03 19:54:44.690208	0.70	4683.00
145	\N	44	2024-07-02	7560.00	1	2025-08-03 19:54:44.889981	2025-08-03 19:54:44.889981	0.49	3692.19
146	\N	80	2024-07-02	4100.00	1	2025-08-03 19:54:45.125219	2025-08-03 19:54:45.125219	0.60	2460.00
147	\N	106	2024-07-02	13490.00	1	2025-08-03 19:54:45.623131	2025-08-03 19:54:45.623131	0.75	10117.50
148	\N	52	2024-07-02	4700.00	1	2025-08-03 19:54:45.813669	2025-08-03 19:54:45.813669	0.60	2820.00
149	\N	53	2024-07-02	3545.00	1	2025-08-03 19:54:46.058716	2025-08-03 19:54:46.058716	0.62	2214.00
150	\N	53	2024-07-02	1165.00	1	2025-08-03 19:54:46.260729	2025-08-03 19:54:46.260729	0.86	1000.00
151	\N	43	2024-07-03	5805.00	1	2025-08-03 19:54:46.501031	2025-08-03 19:54:46.501031	0.65	3773.25
152	\N	43	2024-07-03	5065.00	1	2025-08-03 19:54:46.728666	2025-08-03 19:54:46.728666	0.50	2532.50
153	\N	43	2024-07-03	2431.80	1	2025-08-03 19:54:46.953291	2025-08-03 19:54:46.953291	0.25	597.50
154	\N	44	2024-07-03	5925.00	1	2025-08-03 19:54:47.198129	2025-08-03 19:54:47.198129	0.54	3173.85
155	\N	44	2024-07-03	6525.00	1	2025-08-03 19:54:47.474615	2025-08-03 19:54:47.474615	0.51	3356.17
156	\N	44	2024-07-03	1790.00	1	2025-08-03 19:54:47.655279	2025-08-03 19:54:47.655279	0.55	990.00
157	\N	44	2024-07-03	7050.00	1	2025-08-03 19:54:47.983969	2025-08-03 19:54:47.983969	0.50	3557.28
158	\N	44	2024-07-03	8260.00	1	2025-08-03 19:54:48.210552	2025-08-03 19:54:48.210552	0.40	3296.13
159	\N	45	2024-07-03	2140.00	1	2025-08-03 19:54:48.540671	2025-08-03 19:54:48.540671	0.50	1070.00
160	\N	45	2024-07-03	8425.00	1	2025-08-03 19:54:48.779691	2025-08-03 19:54:48.779691	0.45	3766.00
161	\N	103	2024-07-03	2540.00	1	2025-08-03 19:54:48.989736	2025-08-03 19:54:48.989736	0.60	1525.00
162	\N	48	2024-07-03	4130.00	1	2025-08-03 19:54:49.217762	2025-08-03 19:54:49.217762	0.53	2200.00
163	\N	107	2024-07-03	11850.00	1	2025-08-03 19:54:49.649393	2025-08-03 19:54:49.649393	0.15	1777.50
164	\N	107	2024-07-03	13475.00	1	2025-08-03 19:54:49.861419	2025-08-03 19:54:49.861419	0.20	2695.00
165	\N	102	2024-07-03	3075.00	1	2025-08-03 19:54:50.133483	2025-08-03 19:54:50.133483	0.55	1691.25
166	\N	102	2024-07-03	3840.00	1	2025-08-03 19:54:50.359907	2025-08-03 19:54:50.359907	0.55	2112.00
167	\N	102	2024-07-03	875.00	1	2025-08-03 19:54:50.697797	2025-08-03 19:54:50.697797	0.50	437.50
168	\N	108	2024-07-03	10730.00	1	2025-08-03 19:54:51.20738	2025-08-03 19:54:51.20738	0.40	4292.00
169	\N	52	2024-07-03	2705.00	1	2025-08-03 19:54:51.459277	2025-08-03 19:54:51.459277	0.40	1082.00
170	\N	57	2024-07-03	4055.00	1	2025-08-03 19:54:51.778018	2025-08-03 19:54:51.778018	0.63	2555.00
171	\N	53	2024-07-03	7585.00	1	2025-08-03 19:54:52.026034	2025-08-03 19:54:52.026034	0.70	5300.00
172	\N	53	2024-07-03	8040.00	1	2025-08-03 19:54:52.282616	2025-08-03 19:54:52.282616	0.87	7000.00
173	\N	44	2024-07-08	5370.00	1	2025-08-03 19:54:52.525667	2025-08-03 19:54:52.525667	0.70	3759.00
174	\N	44	2024-07-08	8320.00	1	2025-08-03 19:54:52.734332	2025-08-03 19:54:52.734332	0.85	7086.67
175	\N	44	2024-07-08	4385.00	1	2025-08-03 19:54:52.96615	2025-08-03 19:54:52.96615	0.70	3069.50
176	\N	44	2024-07-08	6795.00	1	2025-08-03 19:54:53.151376	2025-08-03 19:54:53.151376	0.55	3729.00
177	\N	44	2024-07-08	1255.00	1	2025-08-03 19:54:53.386308	2025-08-03 19:54:53.386308	0.70	880.00
178	\N	44	2024-07-08	3855.00	1	2025-08-03 19:54:53.604274	2025-08-03 19:54:53.604274	0.34	1327.40
179	\N	44	2024-07-08	4625.00	1	2025-08-03 19:54:53.836479	2025-08-03 19:54:53.836479	0.27	1231.33
180	\N	45	2024-07-08	6925.00	1	2025-08-03 19:54:54.065884	2025-08-03 19:54:54.065884	0.50	3462.50
181	\N	45	2024-07-08	9730.00	1	2025-08-03 19:54:54.307937	2025-08-03 19:54:54.307937	0.50	4865.00
182	\N	45	2024-07-08	4215.00	1	2025-08-03 19:54:54.494788	2025-08-03 19:54:54.494788	0.50	2107.50
183	\N	94	2024-07-08	2770.00	1	2025-08-03 19:54:54.75615	2025-08-03 19:54:54.75615	0.54	1500.00
184	\N	94	2024-07-08	10960.00	1	2025-08-03 19:54:55.025085	2025-08-03 19:54:55.025085	0.60	6575.00
185	\N	94	2024-07-08	10325.00	1	2025-08-03 19:54:55.293323	2025-08-03 19:54:55.293323	0.59	6125.00
186	\N	109	2024-07-08	5875.00	1	2025-08-03 19:54:55.748398	2025-08-03 19:54:55.748398	0.45	2643.00
187	\N	102	2024-07-08	10144.80	1	2025-08-03 19:54:56.007182	2025-08-03 19:54:56.007182	0.49	5015.00
188	\N	110	2024-07-08	5945.00	1	2025-08-03 19:54:56.409051	2025-08-03 19:54:56.409051	0.63	3718.00
189	\N	110	2024-07-08	5975.00	1	2025-08-03 19:54:56.689305	2025-08-03 19:54:56.689305	0.63	3737.50
190	\N	57	2024-07-08	7200.00	1	2025-08-03 19:54:56.952925	2025-08-03 19:54:56.952925	0.60	4300.00
191	\N	44	2024-07-09	10365.00	1	2025-08-03 19:54:57.284218	2025-08-03 19:54:57.284218	0.50	5182.50
192	\N	44	2024-07-09	9015.00	1	2025-08-03 19:54:57.506914	2025-08-03 19:54:57.506914	0.66	5986.66
193	\N	44	2024-07-09	8820.00	1	2025-08-03 19:54:57.895881	2025-08-03 19:54:57.895881	0.70	6174.00
194	\N	44	2024-07-09	4270.00	1	2025-08-03 19:54:58.167955	2025-08-03 19:54:58.167955	0.44	1858.20
195	\N	45	2024-07-09	7040.00	1	2025-08-03 19:54:58.439556	2025-08-03 19:54:58.439556	0.50	3520.00
196	\N	94	2024-07-09	5730.00	1	2025-08-03 19:54:58.72611	2025-08-03 19:54:58.72611	0.70	4000.00
197	\N	52	2024-07-09	4325.00	1	2025-08-03 19:54:58.949517	2025-08-03 19:54:58.949517	0.35	1500.00
198	\N	111	2024-07-09	645.00	1	2025-08-03 19:54:59.410848	2025-08-03 19:54:59.410848	0.47	300.00
199	\N	44	2024-07-10	6885.00	1	2025-08-03 19:54:59.677475	2025-08-03 19:54:59.677475	0.70	4819.50
200	\N	44	2024-07-10	5345.00	1	2025-08-03 19:54:59.922374	2025-08-03 19:54:59.922374	0.70	3741.50
201	\N	44	2024-07-10	2705.00	1	2025-08-03 19:55:00.191001	2025-08-03 19:55:00.191001	0.80	2164.00
202	\N	44	2024-07-10	8330.00	1	2025-08-03 19:55:00.572339	2025-08-03 19:55:00.572339	0.61	5054.90
203	\N	44	2024-07-10	3490.00	1	2025-08-03 19:55:00.83847	2025-08-03 19:55:00.83847	0.70	2443.00
204	\N	44	2024-07-10	7410.00	1	2025-08-03 19:55:01.112491	2025-08-03 19:55:01.112491	0.70	5187.00
205	\N	45	2024-07-10	1995.00	1	2025-08-03 19:55:01.315438	2025-08-03 19:55:01.315438	0.50	997.50
206	\N	45	2024-07-10	7725.00	1	2025-08-03 19:55:01.582536	2025-08-03 19:55:01.582536	0.50	3862.50
207	\N	112	2024-07-10	7870.00	1	2025-08-03 19:55:02.057186	2025-08-03 19:55:02.057186	0.65	5115.50
208	\N	80	2024-07-10	10155.00	1	2025-08-03 19:55:02.322735	2025-08-03 19:55:02.322735	0.70	7108.50
209	\N	102	2024-07-10	7265.00	1	2025-08-03 19:55:02.577703	2025-08-03 19:55:02.577703	0.50	3632.50
210	\N	108	2024-07-10	21295.00	1	2025-08-03 19:55:02.852806	2025-08-03 19:55:02.852806	0.35	7453.25
211	\N	110	2024-07-10	6830.00	1	2025-08-03 19:55:03.124355	2025-08-03 19:55:03.124355	0.55	3756.50
212	\N	53	2024-07-10	3615.00	1	2025-08-03 19:55:03.387336	2025-08-03 19:55:03.387336	0.53	1900.00
213	\N	53	2024-07-10	6565.00	1	2025-08-03 19:55:03.723367	2025-08-03 19:55:03.723367	0.76	5000.00
214	\N	44	2024-07-11	9425.00	1	2025-08-03 19:55:04.04439	2025-08-03 19:55:04.04439	0.41	3870.33
215	\N	44	2024-07-11	8300.00	1	2025-08-03 19:55:04.360739	2025-08-03 19:55:04.360739	0.55	4600.00
216	\N	44	2024-07-11	6470.00	1	2025-08-03 19:55:04.672663	2025-08-03 19:55:04.672663	0.60	3912.00
217	\N	44	2024-07-11	1890.00	1	2025-08-03 19:55:05.005566	2025-08-03 19:55:05.005566	0.70	1323.00
218	\N	44	2024-07-11	4065.00	1	2025-08-03 19:55:05.412964	2025-08-03 19:55:05.412964	0.44	1796.66
219	\N	45	2024-07-11	7820.00	1	2025-08-03 19:55:05.677662	2025-08-03 19:55:05.677662	0.50	3910.00
220	\N	113	2024-07-11	5320.00	1	2025-08-03 19:55:06.286676	2025-08-03 19:55:06.286676	0.56	3000.00
221	\N	71	2024-07-11	9660.00	1	2025-08-03 19:55:06.58027	2025-08-03 19:55:06.58027	0.42	4037.20
222	\N	102	2024-07-11	5505.00	1	2025-08-03 19:55:06.811739	2025-08-03 19:55:06.811739	0.50	2752.50
223	\N	102	2024-07-11	3920.00	1	2025-08-03 19:55:07.07588	2025-08-03 19:55:07.07588	0.50	1960.00
224	\N	110	2024-07-11	6855.00	1	2025-08-03 19:55:07.449867	2025-08-03 19:55:07.449867	0.65	4455.75
225	\N	52	2024-07-11	10015.00	1	2025-08-03 19:55:07.741275	2025-08-03 19:55:07.741275	0.40	4006.00
226	\N	57	2024-07-11	1605.00	1	2025-08-03 19:55:08.061749	2025-08-03 19:55:08.061749	0.69	1105.00
227	\N	57	2024-07-11	13000.00	1	2025-08-03 19:55:08.358629	2025-08-03 19:55:08.358629	0.45	5890.00
228	\N	44	2024-07-12	7505.00	1	2025-08-03 19:55:08.677537	2025-08-03 19:55:08.677537	0.70	5253.50
229	\N	114	2024-07-12	8600.00	1	2025-08-03 19:55:09.229188	2025-08-03 19:55:09.229188	0.49	4200.00
230	\N	114	2024-07-12	9965.00	1	2025-08-03 19:55:09.477403	2025-08-03 19:55:09.477403	0.45	4500.00
231	\N	114	2024-07-12	10085.00	1	2025-08-03 19:55:09.772339	2025-08-03 19:55:09.772339	0.50	5000.00
232	\N	103	2024-07-12	10875.00	1	2025-08-03 19:55:10.039174	2025-08-03 19:55:10.039174	0.61	6600.00
233	\N	43	2024-07-15	7485.00	1	2025-08-03 19:55:10.296763	2025-08-03 19:55:10.296763	0.60	4491.00
234	\N	43	2024-07-15	4690.00	1	2025-08-03 19:55:10.567796	2025-08-03 19:55:10.567796	0.65	3048.00
235	\N	43	2024-07-15	11355.00	1	2025-08-03 19:55:10.820473	2025-08-03 19:55:10.820473	0.50	5677.50
236	\N	43	2024-07-15	7705.00	1	2025-08-03 19:55:11.095823	2025-08-03 19:55:11.095823	0.60	4623.00
237	\N	44	2024-07-15	8395.00	1	2025-08-03 19:55:11.492265	2025-08-03 19:55:11.492265	0.68	5713.46
238	\N	115	2024-07-15	1810.00	1	2025-08-03 19:55:11.968491	2025-08-03 19:55:11.968491	0.25	452.50
239	\N	88	2024-07-15	11230.00	1	2025-08-03 19:55:12.19448	2025-08-03 19:55:12.19448	0.62	6962.60
240	\N	88	2024-07-15	7445.00	1	2025-08-03 19:55:12.468878	2025-08-03 19:55:12.468878	0.60	4467.00
241	\N	88	2024-07-15	6690.00	1	2025-08-03 19:55:12.774752	2025-08-03 19:55:12.774752	0.62	4147.80
242	\N	94	2024-07-15	5935.00	1	2025-08-03 19:55:13.06468	2025-08-03 19:55:13.06468	0.60	3540.00
243	\N	80	2024-07-15	14050.00	1	2025-08-03 19:55:13.325873	2025-08-03 19:55:13.325873	0.60	8430.00
244	\N	102	2024-07-15	3890.00	1	2025-08-03 19:55:13.541551	2025-08-03 19:55:13.541551	0.50	1945.00
245	\N	116	2024-07-15	4605.00	1	2025-08-03 19:55:14.002322	2025-08-03 19:55:14.002322	0.50	2302.50
246	\N	57	2024-07-15	3155.00	1	2025-08-03 19:55:14.227374	2025-08-03 19:55:14.227374	0.92	2905.00
247	\N	57	2024-07-15	3540.00	1	2025-08-03 19:55:14.497818	2025-08-03 19:55:14.497818	0.55	1940.00
248	\N	44	2024-07-16	7000.00	1	2025-08-03 19:55:14.759776	2025-08-03 19:55:14.759776	0.49	3456.40
249	\N	44	2024-07-16	7445.00	1	2025-08-03 19:55:15.00351	2025-08-03 19:55:15.00351	0.46	3437.66
250	\N	44	2024-07-16	3760.00	1	2025-08-03 19:55:15.278164	2025-08-03 19:55:15.278164	0.40	1500.00
251	\N	44	2024-07-16	8355.00	1	2025-08-03 19:55:15.508146	2025-08-03 19:55:15.508146	0.70	5848.50
252	\N	44	2024-07-16	10620.00	1	2025-08-03 19:55:16.067871	2025-08-03 19:55:16.067871	0.60	6372.00
253	\N	44	2024-07-16	9855.00	1	2025-08-03 19:55:16.292093	2025-08-03 19:55:16.292093	0.66	6530.51
254	\N	44	2024-07-16	8130.00	1	2025-08-03 19:55:16.556346	2025-08-03 19:55:16.556346	0.70	5691.00
255	\N	44	2024-07-16	2310.00	1	2025-08-03 19:55:16.823063	2025-08-03 19:55:16.823063	0.70	1617.00
256	\N	45	2024-07-16	5860.00	1	2025-08-03 19:55:17.099414	2025-08-03 19:55:17.099414	0.42	2466.00
257	\N	88	2024-07-16	12265.00	1	2025-08-03 19:55:17.36284	2025-08-03 19:55:17.36284	0.47	5764.55
258	\N	55	2024-07-16	8910.00	1	2025-08-03 19:55:17.705316	2025-08-03 19:55:17.705316	0.35	3118.50
259	\N	53	2024-07-16	5505.00	1	2025-08-03 19:55:17.975502	2025-08-03 19:55:17.975502	0.65	3600.00
260	\N	44	2024-07-17	11755.00	1	2025-08-03 19:55:18.239806	2025-08-03 19:55:18.239806	0.35	4149.60
261	\N	44	2024-07-17	10225.00	1	2025-08-03 19:55:18.511471	2025-08-03 19:55:18.511471	0.28	2890.50
262	\N	44	2024-07-17	4740.00	1	2025-08-03 19:55:18.879578	2025-08-03 19:55:18.879578	0.50	2363.60
263	\N	44	2024-07-17	2700.00	1	2025-08-03 19:55:19.099756	2025-08-03 19:55:19.099756	0.67	1800.00
264	\N	44	2024-07-17	4975.00	1	2025-08-03 19:55:19.367982	2025-08-03 19:55:19.367982	0.35	1726.33
265	\N	45	2024-07-17	7230.00	1	2025-08-03 19:55:19.740926	2025-08-03 19:55:19.740926	0.47	3431.41
266	\N	96	2024-07-17	3830.00	1	2025-08-03 19:55:20.00282	2025-08-03 19:55:20.00282	0.55	2106.50
267	\N	88	2024-07-17	12220.00	1	2025-08-03 19:55:20.387321	2025-08-03 19:55:20.387321	0.48	5837.13
268	\N	94	2024-07-17	4925.00	1	2025-08-03 19:55:20.772578	2025-08-03 19:55:20.772578	0.57	2800.00
269	\N	58	2024-07-17	1630.00	1	2025-08-03 19:55:21.054449	2025-08-03 19:55:21.054449	0.30	494.88
270	\N	117	2024-07-17	2355.00	1	2025-08-03 19:55:21.509387	2025-08-03 19:55:21.509387	0.50	1177.50
271	110	48	2024-07-17	6855.00	1	2025-08-03 19:55:21.748172	2025-08-03 19:55:21.748172	0.55	3770.25
272	\N	55	2024-07-17	5720.00	1	2025-08-03 19:55:22.008255	2025-08-03 19:55:22.008255	0.35	2002.00
273	\N	102	2024-07-17	7465.00	1	2025-08-03 19:55:22.328156	2025-08-03 19:55:22.328156	0.55	4105.75
274	\N	52	2024-07-17	12645.00	1	2025-08-03 19:55:22.543211	2025-08-03 19:55:22.543211	0.50	6322.50
275	\N	116	2024-07-17	4550.00	1	2025-08-03 19:55:22.808949	2025-08-03 19:55:22.808949	0.55	2502.50
276	\N	116	2024-07-17	10325.00	1	2025-08-03 19:55:23.075357	2025-08-03 19:55:23.075357	0.50	5162.50
277	\N	53	2024-07-17	5115.00	1	2025-08-03 19:55:23.435221	2025-08-03 19:55:23.435221	0.53	2730.00
278	\N	111	2024-07-17	10075.00	1	2025-08-03 19:55:23.711877	2025-08-03 19:55:23.711877	0.60	6000.00
279	\N	44	2024-07-18	7230.00	1	2025-08-03 19:55:23.994954	2025-08-03 19:55:23.994954	0.32	2281.80
280	\N	118	2024-07-18	11060.00	1	2025-08-03 19:55:24.416512	2025-08-03 19:55:24.416512	0.65	7243.53
281	\N	83	2024-07-18	6500.00	1	2025-08-03 19:55:24.689483	2025-08-03 19:55:24.689483	0.50	3237.50
282	\N	55	2024-07-18	6640.00	1	2025-08-03 19:55:24.954445	2025-08-03 19:55:24.954445	0.49	3246.67
283	\N	55	2024-07-18	9615.00	1	2025-08-03 19:55:25.220268	2025-08-03 19:55:25.220268	0.35	3365.25
284	\N	55	2024-07-18	8870.00	1	2025-08-03 19:55:25.487041	2025-08-03 19:55:25.487041	0.40	3548.00
285	\N	57	2024-07-18	500.00	1	2025-08-03 19:55:25.817684	2025-08-03 19:55:25.817684	0.80	400.00
286	\N	60	2024-07-18	10360.00	1	2025-08-03 19:55:26.101884	2025-08-03 19:55:26.101884	0.46	4723.80
287	\N	44	2024-07-19	6940.00	1	2025-08-03 19:55:26.3756	2025-08-03 19:55:26.3756	0.60	4164.00
288	\N	112	2024-07-19	3505.00	1	2025-08-03 19:55:26.666572	2025-08-03 19:55:26.666572	0.70	2453.50
289	\N	119	2024-07-19	3260.00	1	2025-08-03 19:55:27.09449	2025-08-03 19:55:27.09449	0.46	1500.00
290	\N	88	2024-07-19	9970.00	1	2025-08-03 19:55:27.362002	2025-08-03 19:55:27.362002	0.51	5084.70
291	\N	52	2024-07-19	7490.00	1	2025-08-03 19:55:27.578878	2025-08-03 19:55:27.578878	0.47	3520.00
292	\N	53	2024-07-19	7790.00	1	2025-08-03 19:55:27.859051	2025-08-03 19:55:27.859051	0.69	5400.00
293	\N	53	2024-07-19	7790.00	1	2025-08-03 19:55:28.138793	2025-08-03 19:55:28.138793	0.69	5400.00
294	\N	44	2024-07-22	6970.00	1	2025-08-03 19:55:28.512378	2025-08-03 19:55:28.512378	0.41	2828.06
295	\N	44	2024-07-22	4005.00	1	2025-08-03 19:55:28.783706	2025-08-03 19:55:28.783706	0.12	500.00
296	\N	120	2024-07-22	12120.00	1	2025-08-03 19:55:29.427954	2025-08-03 19:55:29.427954	0.60	7272.00
297	\N	80	2024-07-22	9265.00	1	2025-08-03 19:55:29.662485	2025-08-03 19:55:29.662485	0.35	3242.75
298	\N	102	2024-07-22	1270.00	1	2025-08-03 19:55:29.907885	2025-08-03 19:55:29.907885	0.75	952.50
299	\N	102	2024-07-22	550.00	1	2025-08-03 19:55:30.182729	2025-08-03 19:55:30.182729	0.75	412.50
300	\N	52	2024-07-22	9575.00	1	2025-08-03 19:55:30.440439	2025-08-03 19:55:30.440439	0.50	4787.50
301	\N	53	2024-07-22	6590.00	1	2025-08-03 19:55:30.707498	2025-08-03 19:55:30.707498	0.79	5200.00
302	\N	44	2024-07-23	7400.00	1	2025-08-03 19:55:30.971065	2025-08-03 19:55:30.971065	0.62	4621.66
303	\N	44	2024-07-23	6330.00	1	2025-08-03 19:55:31.249048	2025-08-03 19:55:31.249048	0.60	3798.00
304	\N	44	2024-07-23	11480.00	1	2025-08-03 19:55:31.526599	2025-08-03 19:55:31.526599	0.48	5515.23
305	\N	45	2024-07-23	4075.00	1	2025-08-03 19:55:31.813535	2025-08-03 19:55:31.813535	0.50	2037.50
306	\N	45	2024-07-23	2140.00	1	2025-08-03 19:55:32.097035	2025-08-03 19:55:32.097035	0.50	1070.00
307	\N	45	2024-07-23	6310.00	1	2025-08-03 19:55:32.367901	2025-08-03 19:55:32.367901	0.50	3155.00
308	\N	120	2024-07-23	3755.00	1	2025-08-03 19:55:32.581249	2025-08-03 19:55:32.581249	0.60	2253.00
309	\N	120	2024-07-23	3325.00	1	2025-08-03 19:55:32.869605	2025-08-03 19:55:32.869605	0.50	1662.00
310	\N	121	2024-07-23	7250.00	1	2025-08-03 19:55:33.343193	2025-08-03 19:55:33.343193	0.50	3625.00
311	\N	122	2024-07-23	2540.00	1	2025-08-03 19:55:33.920519	2025-08-03 19:55:33.920519	0.60	1524.00
312	\N	55	2024-07-23	6145.00	1	2025-08-03 19:55:34.196298	2025-08-03 19:55:34.196298	0.40	2458.00
313	\N	123	2024-07-23	9630.00	1	2025-08-03 19:55:34.671019	2025-08-03 19:55:34.671019	0.67	6420.00
314	\N	44	2024-07-24	3695.00	1	2025-08-03 19:55:35.04362	2025-08-03 19:55:35.04362	0.42	1548.33
315	\N	44	2024-07-24	7105.00	1	2025-08-03 19:55:35.308978	2025-08-03 19:55:35.308978	0.43	3071.00
316	\N	44	2024-07-24	6360.00	1	2025-08-03 19:55:35.671348	2025-08-03 19:55:35.671348	0.43	2722.66
317	\N	44	2024-07-24	4500.00	1	2025-08-03 19:55:35.933898	2025-08-03 19:55:35.933898	0.53	2401.66
318	\N	44	2024-07-24	9610.00	1	2025-08-03 19:55:36.216548	2025-08-03 19:55:36.216548	0.45	4292.33
319	\N	44	2024-07-24	7405.00	1	2025-08-03 19:55:36.508735	2025-08-03 19:55:36.508735	0.42	3135.00
320	\N	89	2024-07-24	550.00	1	2025-08-03 19:55:36.970052	2025-08-03 19:55:36.970052	0.73	400.00
321	\N	48	2024-07-24	5290.00	1	2025-08-03 19:55:37.311659	2025-08-03 19:55:37.311659	0.65	3438.50
322	\N	48	2024-07-24	930.00	1	2025-08-03 19:55:37.590777	2025-08-03 19:55:37.590777	0.30	280.00
323	\N	124	2024-07-24	10500.00	1	2025-08-03 19:55:38.031791	2025-08-03 19:55:38.031791	0.64	6727.50
324	\N	60	2024-07-24	4940.00	1	2025-08-03 19:55:38.328743	2025-08-03 19:55:38.328743	0.60	2964.00
325	\N	60	2024-07-24	6465.00	1	2025-08-03 19:55:38.678552	2025-08-03 19:55:38.678552	0.50	3232.50
326	\N	53	2024-07-24	6275.00	1	2025-08-03 19:55:38.908127	2025-08-03 19:55:38.908127	0.69	4300.00
327	\N	44	2024-07-25	3480.00	1	2025-08-03 19:55:39.132072	2025-08-03 19:55:39.132072	0.43	1510.08
328	\N	44	2024-07-25	545.00	1	2025-08-03 19:55:39.366168	2025-08-03 19:55:39.366168	0.70	380.00
329	\N	44	2024-07-25	11245.00	1	2025-08-03 19:55:39.603565	2025-08-03 19:55:39.603565	0.57	6420.00
330	\N	124	2024-07-25	6920.00	1	2025-08-03 19:55:40.150703	2025-08-03 19:55:40.150703	0.59	4113.00
331	\N	102	2024-07-25	3656.73	1	2025-08-03 19:55:40.469642	2025-08-03 19:55:40.469642	0.70	2559.71
332	\N	102	2024-07-25	3980.00	1	2025-08-03 19:55:40.690739	2025-08-03 19:55:40.690739	0.70	2786.00
333	\N	102	2024-07-25	7170.00	1	2025-08-03 19:55:40.898139	2025-08-03 19:55:40.898139	0.75	5377.50
334	\N	102	2024-07-25	9640.00	1	2025-08-03 19:55:41.082096	2025-08-03 19:55:41.082096	0.50	4820.00
335	\N	52	2024-07-25	2710.00	1	2025-08-03 19:55:41.322368	2025-08-03 19:55:41.322368	0.50	1355.00
336	\N	53	2024-07-25	1155.00	1	2025-08-03 19:55:41.533029	2025-08-03 19:55:41.533029	0.87	1000.00
337	\N	53	2024-07-25	1100.00	1	2025-08-03 19:55:41.78445	2025-08-03 19:55:41.78445	0.91	1000.00
338	\N	53	2024-07-25	6610.00	1	2025-08-03 19:55:41.992684	2025-08-03 19:55:41.992684	0.61	4000.00
339	\N	44	2024-07-26	9745.00	1	2025-08-03 19:55:42.174162	2025-08-03 19:55:42.174162	0.29	2812.33
340	\N	44	2024-07-26	3460.00	1	2025-08-03 19:55:42.388398	2025-08-03 19:55:42.388398	0.42	1459.57
341	\N	44	2024-07-26	6930.00	1	2025-08-03 19:55:42.585328	2025-08-03 19:55:42.585328	0.60	4135.33
342	\N	44	2024-07-26	6220.00	1	2025-08-03 19:55:42.853928	2025-08-03 19:55:42.853928	0.39	2449.13
343	\N	102	2024-07-26	8080.00	1	2025-08-03 19:55:43.100332	2025-08-03 19:55:43.100332	0.60	4848.00
344	\N	52	2024-07-26	6260.00	1	2025-08-03 19:55:43.327277	2025-08-03 19:55:43.327277	0.52	3245.00
345	\N	116	2024-07-26	1670.00	1	2025-08-03 19:55:43.576932	2025-08-03 19:55:43.576932	0.55	918.50
346	\N	44	2024-07-29	6900.00	1	2025-08-03 19:55:43.845443	2025-08-03 19:55:43.845443	0.70	4800.00
347	\N	44	2024-07-29	7265.00	1	2025-08-03 19:55:44.2282	2025-08-03 19:55:44.2282	0.54	3948.66
348	\N	44	2024-07-29	935.00	1	2025-08-03 19:55:44.561373	2025-08-03 19:55:44.561373	0.69	645.00
349	\N	44	2024-07-29	7675.00	1	2025-08-03 19:55:44.841668	2025-08-03 19:55:44.841668	0.70	5372.50
350	\N	44	2024-07-29	8325.00	1	2025-08-03 19:55:45.085451	2025-08-03 19:55:45.085451	0.81	6731.66
351	\N	44	2024-07-29	5880.00	1	2025-08-03 19:55:45.28882	2025-08-03 19:55:45.28882	0.36	2115.33
352	\N	44	2024-07-29	7515.00	1	2025-08-03 19:55:45.497008	2025-08-03 19:55:45.497008	0.84	6281.42
353	\N	44	2024-07-29	8990.00	1	2025-08-03 19:55:45.854323	2025-08-03 19:55:45.854323	0.70	6290.00
354	\N	117	2024-07-29	6175.00	1	2025-08-03 19:55:46.122029	2025-08-03 19:55:46.122029	0.57	3525.72
355	\N	125	2024-07-29	1395.00	1	2025-08-03 19:55:46.471816	2025-08-03 19:55:46.471816	0.50	697.50
356	\N	124	2024-07-29	7956.40	1	2025-08-03 19:55:46.696802	2025-08-03 19:55:46.696802	0.50	3942.50
357	\N	55	2024-07-29	3925.00	1	2025-08-03 19:55:47.188436	2025-08-03 19:55:47.188436	0.50	1962.50
358	\N	102	2024-07-29	5280.00	1	2025-08-03 19:55:47.485488	2025-08-03 19:55:47.485488	0.75	3960.00
359	\N	110	2024-07-29	6900.00	1	2025-08-03 19:55:47.818427	2025-08-03 19:55:47.818427	0.50	3430.00
360	\N	126	2024-07-29	9575.00	1	2025-08-03 19:55:48.301996	2025-08-03 19:55:48.301996	0.50	4787.50
361	\N	57	2024-07-29	13930.00	1	2025-08-03 19:55:48.613924	2025-08-03 19:55:48.613924	0.36	5000.00
362	\N	44	2024-07-30	8740.00	1	2025-08-03 19:55:48.904731	2025-08-03 19:55:48.904731	0.68	5985.00
363	\N	44	2024-07-30	4230.00	1	2025-08-03 19:55:49.196478	2025-08-03 19:55:49.196478	0.50	2109.50
364	\N	44	2024-07-30	9755.00	1	2025-08-03 19:55:49.479802	2025-08-03 19:55:49.479802	0.69	6762.00
365	\N	44	2024-07-30	6865.00	1	2025-08-03 19:55:49.819352	2025-08-03 19:55:49.819352	0.75	5167.97
366	\N	44	2024-07-30	6540.00	1	2025-08-03 19:55:50.091191	2025-08-03 19:55:50.091191	0.44	2854.82
367	\N	44	2024-07-30	4775.00	1	2025-08-03 19:55:50.453012	2025-08-03 19:55:50.453012	0.34	1628.01
368	\N	44	2024-07-30	2700.00	1	2025-08-03 19:55:50.862063	2025-08-03 19:55:50.862063	0.70	1890.00
369	\N	44	2024-07-30	7270.00	1	2025-08-03 19:55:51.153088	2025-08-03 19:55:51.153088	0.68	4970.00
370	\N	44	2024-07-30	7950.00	1	2025-08-03 19:55:51.410787	2025-08-03 19:55:51.410787	0.63	5012.00
371	\N	44	2024-07-30	4195.00	1	2025-08-03 19:55:51.838771	2025-08-03 19:55:51.838771	0.31	1320.66
372	\N	45	2024-07-30	7935.00	1	2025-08-03 19:55:52.170348	2025-08-03 19:55:52.170348	0.50	3967.50
373	\N	112	2024-07-30	5880.00	1	2025-08-03 19:55:52.596361	2025-08-03 19:55:52.596361	0.60	3528.00
374	\N	127	2024-07-30	9980.00	1	2025-08-03 19:55:53.184351	2025-08-03 19:55:53.184351	0.55	5489.00
375	\N	88	2024-07-30	7760.00	1	2025-08-03 19:55:53.56721	2025-08-03 19:55:53.56721	0.37	2839.37
376	\N	86	2024-07-30	2910.00	1	2025-08-03 19:55:53.872096	2025-08-03 19:55:53.872096	0.65	1892.00
377	\N	102	2024-07-30	7755.00	1	2025-08-03 19:55:54.170836	2025-08-03 19:55:54.170836	0.77	6000.00
378	\N	52	2024-07-30	2135.00	1	2025-08-03 19:55:54.443529	2025-08-03 19:55:54.443529	0.50	1067.50
379	\N	52	2024-07-30	2785.00	1	2025-08-03 19:55:54.709527	2025-08-03 19:55:54.709527	0.50	1392.50
380	\N	53	2024-07-30	8255.00	1	2025-08-03 19:55:54.998292	2025-08-03 19:55:54.998292	0.73	6000.00
381	\N	43	2024-07-31	7675.00	1	2025-08-03 19:55:55.288545	2025-08-03 19:55:55.288545	0.50	3837.50
382	\N	43	2024-07-31	3640.00	1	2025-08-03 19:55:55.578137	2025-08-03 19:55:55.578137	0.50	1820.00
383	\N	43	2024-07-31	5910.00	1	2025-08-03 19:55:55.935156	2025-08-03 19:55:55.935156	0.60	3546.00
384	\N	44	2024-07-31	5825.00	1	2025-08-03 19:55:56.200093	2025-08-03 19:55:56.200093	0.70	4077.50
385	\N	44	2024-07-31	10270.00	1	2025-08-03 19:55:56.464187	2025-08-03 19:55:56.464187	0.43	4448.66
386	\N	44	2024-07-31	5475.00	1	2025-08-03 19:55:56.75312	2025-08-03 19:55:56.75312	0.30	1638.37
387	\N	44	2024-07-31	7790.00	1	2025-08-03 19:55:56.986101	2025-08-03 19:55:56.986101	0.49	3846.66
388	\N	44	2024-07-31	1025.00	1	2025-08-03 19:55:57.219062	2025-08-03 19:55:57.219062	0.43	440.52
389	\N	44	2024-07-31	975.00	1	2025-08-03 19:55:57.501896	2025-08-03 19:55:57.501896	0.69	675.00
390	\N	44	2024-07-31	4305.00	1	2025-08-03 19:55:57.744689	2025-08-03 19:55:57.744689	0.60	2583.00
391	\N	71	2024-07-31	3615.00	1	2025-08-03 19:55:58.043185	2025-08-03 19:55:58.043185	0.60	2169.00
392	\N	83	2024-07-31	5383.60	1	2025-08-03 19:55:58.340819	2025-08-03 19:55:58.340819	0.50	2667.50
393	\N	52	2024-07-31	8460.00	1	2025-08-03 19:55:58.598152	2025-08-03 19:55:58.598152	0.50	4230.00
394	\N	128	2024-07-31	5845.00	1	2025-08-03 19:55:59.007363	2025-08-03 19:55:59.007363	0.35	2045.75
395	\N	128	2024-07-31	6405.00	1	2025-08-03 19:55:59.433501	2025-08-03 19:55:59.433501	0.33	2115.75
396	\N	60	2024-07-31	5265.00	1	2025-08-03 19:55:59.829059	2025-08-03 19:55:59.829059	0.50	2632.50
397	\N	60	2024-07-31	3780.00	1	2025-08-03 19:56:00.072784	2025-08-03 19:56:00.072784	0.64	2401.95
398	\N	60	2024-07-31	3445.00	1	2025-08-03 19:56:00.524864	2025-08-03 19:56:00.524864	0.70	2411.50
399	\N	129	2024-07-31	5755.00	1	2025-08-03 19:56:00.977518	2025-08-03 19:56:00.977518	0.65	3740.75
400	\N	129	2024-07-31	7990.00	1	2025-08-03 19:56:01.214382	2025-08-03 19:56:01.214382	0.65	5193.50
401	\N	130	2024-08-01	9333.80	1	2025-08-03 19:56:01.813899	2025-08-03 19:56:01.813899	0.60	5629.00
402	\N	44	2024-08-01	6750.00	1	2025-08-03 19:56:02.192206	2025-08-03 19:56:02.192206	0.70	4720.00
403	\N	44	2024-08-01	7475.00	1	2025-08-03 19:56:02.499454	2025-08-03 19:56:02.499454	0.57	4232.50
404	\N	44	2024-08-01	4230.00	1	2025-08-03 19:56:02.794707	2025-08-03 19:56:02.794707	0.34	1432.88
405	\N	44	2024-08-01	6740.00	1	2025-08-03 19:56:03.022246	2025-08-03 19:56:03.022246	0.64	4339.82
406	\N	71	2024-08-01	3365.00	1	2025-08-03 19:56:03.314529	2025-08-03 19:56:03.314529	0.40	1346.00
407	\N	80	2024-08-01	5965.00	1	2025-08-03 19:56:03.616748	2025-08-03 19:56:03.616748	0.65	3877.25
408	\N	80	2024-08-01	3040.00	1	2025-08-03 19:56:03.965927	2025-08-03 19:56:03.965927	0.65	1976.00
409	\N	55	2024-08-01	720.00	1	2025-08-03 19:56:04.226273	2025-08-03 19:56:04.226273	0.35	252.00
410	\N	55	2024-08-01	5840.00	1	2025-08-03 19:56:04.498309	2025-08-03 19:56:04.498309	0.45	2628.00
411	\N	126	2024-08-01	705.00	1	2025-08-03 19:56:04.771268	2025-08-03 19:56:04.771268	0.67	475.00
412	\N	126	2024-08-01	735.00	1	2025-08-03 19:56:05.092499	2025-08-03 19:56:05.092499	0.58	425.00
413	\N	44	2024-08-02	11430.00	1	2025-08-03 19:56:05.441452	2025-08-03 19:56:05.441452	0.52	5910.37
414	\N	45	2024-08-02	8940.00	1	2025-08-03 19:56:05.707106	2025-08-03 19:56:05.707106	0.50	4470.00
415	\N	120	2024-08-02	5910.00	1	2025-08-03 19:56:05.982394	2025-08-03 19:56:05.982394	0.60	3546.00
416	\N	64	2024-08-02	4075.00	1	2025-08-03 19:56:06.228917	2025-08-03 19:56:06.228917	0.60	2445.00
417	\N	131	2024-08-02	11110.00	1	2025-08-03 19:56:06.670817	2025-08-03 19:56:06.670817	0.67	7443.70
418	\N	52	2024-08-02	1990.00	1	2025-08-03 19:56:06.926094	2025-08-03 19:56:06.926094	0.50	995.00
419	\N	116	2024-08-02	5690.00	1	2025-08-03 19:56:07.21192	2025-08-03 19:56:07.21192	0.51	2901.90
420	\N	60	2024-08-02	7425.00	1	2025-08-03 19:56:07.462769	2025-08-03 19:56:07.462769	0.50	3712.50
421	\N	53	2024-08-02	5410.00	1	2025-08-03 19:56:07.730077	2025-08-03 19:56:07.730077	0.60	3234.00
422	\N	53	2024-08-02	3290.00	1	2025-08-03 19:56:07.994417	2025-08-03 19:56:07.994417	0.50	1645.00
423	\N	44	2024-08-05	8660.00	1	2025-08-03 19:56:08.369843	2025-08-03 19:56:08.369843	0.70	6062.00
424	\N	44	2024-08-05	6850.00	1	2025-08-03 19:56:08.739802	2025-08-03 19:56:08.739802	0.60	4110.00
425	\N	44	2024-08-05	3030.00	1	2025-08-03 19:56:09.018648	2025-08-03 19:56:09.018648	0.18	551.43
426	\N	44	2024-08-05	3900.00	1	2025-08-03 19:56:09.287872	2025-08-03 19:56:09.287872	0.67	2628.33
427	\N	94	2024-08-05	11005.00	1	2025-08-03 19:56:09.523781	2025-08-03 19:56:09.523781	0.60	6603.00
428	\N	66	2024-08-05	4200.00	1	2025-08-03 19:56:09.798778	2025-08-03 19:56:09.798778	0.24	1000.00
429	\N	132	2024-08-05	3065.00	1	2025-08-03 19:56:10.257738	2025-08-03 19:56:10.257738	0.43	1331.73
430	\N	48	2024-08-05	6260.00	1	2025-08-03 19:56:10.489581	2025-08-03 19:56:10.489581	0.55	3443.00
431	\N	133	2024-08-05	7780.00	1	2025-08-03 19:56:10.918313	2025-08-03 19:56:10.918313	0.55	4279.00
432	\N	55	2024-08-05	4270.00	1	2025-08-03 19:56:11.162038	2025-08-03 19:56:11.162038	0.45	1940.97
433	\N	102	2024-08-05	6750.00	1	2025-08-03 19:56:11.421711	2025-08-03 19:56:11.421711	0.75	5062.50
434	\N	57	2024-08-05	2630.00	1	2025-08-03 19:56:11.681255	2025-08-03 19:56:11.681255	0.39	1030.00
435	\N	57	2024-08-05	12755.00	1	2025-08-03 19:56:11.957623	2025-08-03 19:56:11.957623	0.40	5082.00
436	\N	57	2024-08-05	5370.00	1	2025-08-03 19:56:12.199787	2025-08-03 19:56:12.199787	0.61	3270.00
437	\N	44	2024-08-06	7080.00	1	2025-08-03 19:56:12.445453	2025-08-03 19:56:12.445453	0.47	3356.00
438	\N	44	2024-08-06	5500.00	1	2025-08-03 19:56:12.721627	2025-08-03 19:56:12.721627	0.70	3850.00
439	\N	45	2024-08-06	6927.80	1	2025-08-03 19:56:12.981638	2025-08-03 19:56:12.981638	0.50	3452.50
440	\N	79	2024-08-06	8620.00	1	2025-08-03 19:56:13.264212	2025-08-03 19:56:13.264212	0.50	4310.00
441	\N	110	2024-08-06	3585.00	1	2025-08-03 19:56:13.525163	2025-08-03 19:56:13.525163	0.70	2509.50
442	\N	57	2024-08-06	11012.20	1	2025-08-03 19:56:13.732794	2025-08-03 19:56:13.732794	0.69	7591.50
443	\N	57	2024-08-06	10275.00	1	2025-08-03 19:56:14.004281	2025-08-03 19:56:14.004281	0.66	6775.00
444	\N	44	2024-08-07	8965.00	1	2025-08-03 19:56:14.271508	2025-08-03 19:56:14.271508	0.34	3084.46
445	\N	44	2024-08-07	5640.00	1	2025-08-03 19:56:14.539013	2025-08-03 19:56:14.539013	0.13	723.75
446	\N	44	2024-08-07	6670.00	1	2025-08-03 19:56:14.781669	2025-08-03 19:56:14.781669	0.64	4300.83
447	\N	44	2024-08-07	1565.00	1	2025-08-03 19:56:15.054929	2025-08-03 19:56:15.054929	0.46	722.88
448	\N	44	2024-08-07	8095.00	1	2025-08-03 19:56:15.31994	2025-08-03 19:56:15.31994	0.85	6912.00
449	\N	44	2024-08-07	4570.00	1	2025-08-03 19:56:15.689095	2025-08-03 19:56:15.689095	0.60	2742.00
450	\N	44	2024-08-07	8750.00	1	2025-08-03 19:56:15.955248	2025-08-03 19:56:15.955248	0.66	5750.00
451	\N	45	2024-08-07	9660.00	1	2025-08-03 19:56:16.22192	2025-08-03 19:56:16.22192	0.50	4830.00
452	\N	65	2024-08-07	5780.00	1	2025-08-03 19:56:16.584688	2025-08-03 19:56:16.584688	0.50	2890.00
453	\N	57	2024-08-07	11245.00	1	2025-08-03 19:56:16.845303	2025-08-03 19:56:16.845303	0.66	7375.00
454	\N	57	2024-08-07	9490.00	1	2025-08-03 19:56:17.11742	2025-08-03 19:56:17.11742	0.50	4740.00
455	\N	44	2024-08-08	6250.00	1	2025-08-03 19:56:17.423818	2025-08-03 19:56:17.423818	0.70	4375.00
456	\N	44	2024-08-08	5000.00	1	2025-08-03 19:56:17.693359	2025-08-03 19:56:17.693359	0.84	4180.20
457	\N	44	2024-08-08	7280.00	1	2025-08-03 19:56:17.900997	2025-08-03 19:56:17.900997	0.70	5096.00
458	\N	44	2024-08-08	12505.00	1	2025-08-03 19:56:18.266016	2025-08-03 19:56:18.266016	0.24	3052.75
459	\N	44	2024-08-08	7325.00	1	2025-08-03 19:56:18.572578	2025-08-03 19:56:18.572578	0.56	4070.99
460	\N	44	2024-08-08	8785.00	1	2025-08-03 19:56:18.874807	2025-08-03 19:56:18.874807	0.31	2695.00
461	\N	116	2024-08-08	6720.00	1	2025-08-03 19:56:19.100106	2025-08-03 19:56:19.100106	0.45	3024.00
462	\N	57	2024-08-08	9700.00	1	2025-08-03 19:56:19.375006	2025-08-03 19:56:19.375006	0.50	4850.00
463	\N	53	2024-08-08	6400.00	1	2025-08-03 19:56:19.752724	2025-08-03 19:56:19.752724	0.53	3400.00
464	\N	44	2024-08-09	3370.00	1	2025-08-03 19:56:19.969791	2025-08-03 19:56:19.969791	0.36	1221.20
465	\N	44	2024-08-09	5510.00	1	2025-08-03 19:56:20.267322	2025-08-03 19:56:20.267322	0.46	2534.10
466	\N	71	2024-08-09	3460.00	1	2025-08-03 19:56:20.581283	2025-08-03 19:56:20.581283	0.55	1903.00
467	\N	134	2024-08-09	1795.00	1	2025-08-03 19:56:21.080119	2025-08-03 19:56:21.080119	0.50	897.50
468	\N	55	2024-08-09	6220.00	1	2025-08-03 19:56:21.358899	2025-08-03 19:56:21.358899	0.40	2488.00
469	\N	55	2024-08-09	4645.00	1	2025-08-03 19:56:21.626887	2025-08-03 19:56:21.626887	0.40	1858.00
470	\N	102	2024-08-09	5960.00	1	2025-08-03 19:56:21.89775	2025-08-03 19:56:21.89775	0.41	2420.00
471	\N	102	2024-08-09	1135.00	1	2025-08-03 19:56:22.160878	2025-08-03 19:56:22.160878	0.70	794.50
472	\N	44	2024-08-12	6275.00	1	2025-08-03 19:56:22.434399	2025-08-03 19:56:22.434399	0.44	2786.37
473	\N	44	2024-08-12	10020.00	1	2025-08-03 19:56:22.713273	2025-08-03 19:56:22.713273	0.48	4840.50
474	\N	44	2024-08-12	7085.00	1	2025-08-03 19:56:23.001309	2025-08-03 19:56:23.001309	0.60	4251.00
475	\N	135	2024-08-12	12975.00	1	2025-08-03 19:56:23.41444	2025-08-03 19:56:23.41444	0.50	6487.50
476	\N	55	2024-08-12	9690.00	1	2025-08-03 19:56:23.643489	2025-08-03 19:56:23.643489	0.36	3495.28
477	\N	44	2024-08-13	9025.00	1	2025-08-03 19:56:23.968135	2025-08-03 19:56:23.968135	0.71	6372.14
478	\N	44	2024-08-13	3340.00	1	2025-08-03 19:56:24.250035	2025-08-03 19:56:24.250035	0.60	2004.00
479	\N	44	2024-08-13	6855.00	1	2025-08-03 19:56:24.569411	2025-08-03 19:56:24.569411	0.60	4113.00
480	\N	44	2024-08-13	6930.00	1	2025-08-03 19:56:24.869251	2025-08-03 19:56:24.869251	0.38	2637.66
481	\N	44	2024-08-13	1520.00	1	2025-08-03 19:56:25.175357	2025-08-03 19:56:25.175357	0.70	1064.00
482	\N	44	2024-08-13	5850.00	1	2025-08-03 19:56:25.461551	2025-08-03 19:56:25.461551	0.60	3510.00
483	157	44	2024-08-13	4250.00	1	2025-08-03 19:56:25.693622	2025-08-03 19:56:25.693622	0.28	1189.00
484	\N	44	2024-08-13	7390.00	1	2025-08-03 19:56:25.968974	2025-08-03 19:56:25.968974	0.70	5173.00
485	\N	66	2024-08-13	12840.00	1	2025-08-03 19:56:26.414552	2025-08-03 19:56:26.414552	0.53	6800.00
486	\N	55	2024-08-13	3950.00	1	2025-08-03 19:56:26.705719	2025-08-03 19:56:26.705719	0.36	1436.00
487	\N	55	2024-08-13	13710.00	1	2025-08-03 19:56:27.079803	2025-08-03 19:56:27.079803	0.35	4798.50
488	\N	102	2024-08-13	8300.00	1	2025-08-03 19:56:27.364234	2025-08-03 19:56:27.364234	0.55	4565.00
489	\N	110	2024-08-13	4805.00	1	2025-08-03 19:56:27.646618	2025-08-03 19:56:27.646618	0.65	3123.25
490	\N	57	2024-08-13	9735.00	1	2025-08-03 19:56:27.9698	2025-08-03 19:56:27.9698	0.57	5585.00
491	\N	57	2024-08-13	1780.00	1	2025-08-03 19:56:28.286117	2025-08-03 19:56:28.286117	0.44	780.00
492	\N	43	2024-08-14	7235.00	1	2025-08-03 19:56:28.566118	2025-08-03 19:56:28.566118	0.50	3617.50
493	\N	43	2024-08-14	7320.00	1	2025-08-03 19:56:28.879265	2025-08-03 19:56:28.879265	0.50	3660.00
494	\N	43	2024-08-14	3820.00	1	2025-08-03 19:56:29.261918	2025-08-03 19:56:29.261918	0.71	2700.00
495	\N	43	2024-08-14	5265.00	1	2025-08-03 19:56:29.646371	2025-08-03 19:56:29.646371	0.63	3303.00
496	\N	44	2024-08-14	1925.00	1	2025-08-03 19:56:30.025552	2025-08-03 19:56:30.025552	0.70	1347.50
497	\N	44	2024-08-14	7050.00	1	2025-08-03 19:56:30.371631	2025-08-03 19:56:30.371631	0.70	4935.00
498	\N	48	2024-08-14	6520.00	1	2025-08-03 19:56:30.803531	2025-08-03 19:56:30.803531	0.60	3912.00
499	\N	48	2024-08-14	7345.00	1	2025-08-03 19:56:31.152013	2025-08-03 19:56:31.152013	0.60	4407.00
500	\N	55	2024-08-14	8165.00	1	2025-08-03 19:56:31.499981	2025-08-03 19:56:31.499981	0.35	2857.75
501	\N	55	2024-08-14	2405.00	1	2025-08-03 19:56:31.781568	2025-08-03 19:56:31.781568	0.45	1082.25
502	\N	116	2024-08-14	7125.00	1	2025-08-03 19:56:32.05673	2025-08-03 19:56:32.05673	0.45	3206.25
503	\N	44	2024-08-15	5860.00	1	2025-08-03 19:56:32.374752	2025-08-03 19:56:32.374752	0.69	4060.00
504	\N	44	2024-08-15	5320.00	1	2025-08-03 19:56:32.624756	2025-08-03 19:56:32.624756	0.69	3696.00
505	\N	44	2024-08-15	5775.00	1	2025-08-03 19:56:32.909582	2025-08-03 19:56:32.909582	0.70	4042.50
506	\N	44	2024-08-15	3780.00	1	2025-08-03 19:56:33.194994	2025-08-03 19:56:33.194994	0.60	2280.00
507	\N	121	2024-08-15	6962.40	1	2025-08-03 19:56:33.470477	2025-08-03 19:56:33.470477	0.50	3462.50
508	\N	121	2024-08-15	5220.00	1	2025-08-03 19:56:33.750049	2025-08-03 19:56:33.750049	0.50	2610.00
509	\N	136	2024-08-15	1050.00	1	2025-08-03 19:56:34.169295	2025-08-03 19:56:34.169295	0.60	630.00
510	\N	102	2024-08-15	9030.00	1	2025-08-03 19:56:34.387804	2025-08-03 19:56:34.387804	0.70	6321.00
511	\N	44	2024-08-16	6760.00	1	2025-08-03 19:56:34.653973	2025-08-03 19:56:34.653973	0.70	4720.00
512	\N	44	2024-08-16	9140.00	1	2025-08-03 19:56:34.949331	2025-08-03 19:56:34.949331	0.39	3554.33
513	\N	45	2024-08-16	7220.00	1	2025-08-03 19:56:35.276616	2025-08-03 19:56:35.276616	0.42	3000.00
514	\N	137	2024-08-16	9430.00	1	2025-08-03 19:56:35.735799	2025-08-03 19:56:35.735799	0.50	4715.00
515	\N	137	2024-08-16	7745.00	1	2025-08-03 19:56:35.972035	2025-08-03 19:56:35.972035	0.50	3872.50
516	\N	52	2024-08-16	3105.00	1	2025-08-03 19:56:36.219719	2025-08-03 19:56:36.219719	0.50	1552.50
517	\N	123	2024-08-16	6835.00	1	2025-08-03 19:56:36.501837	2025-08-03 19:56:36.501837	0.29	2000.00
518	\N	44	2024-08-19	4355.00	1	2025-08-03 19:56:36.733372	2025-08-03 19:56:36.733372	0.70	3048.50
519	\N	44	2024-08-19	2400.00	1	2025-08-03 19:56:36.976509	2025-08-03 19:56:36.976509	0.59	1420.66
520	\N	44	2024-08-19	3500.00	1	2025-08-03 19:56:37.250732	2025-08-03 19:56:37.250732	0.34	1203.26
521	\N	88	2024-08-19	1179.52	1	2025-08-03 19:56:37.520958	2025-08-03 19:56:37.520958	0.18	212.32
522	\N	52	2024-08-19	7855.00	1	2025-08-03 19:56:37.786468	2025-08-03 19:56:37.786468	0.50	3927.50
523	\N	60	2024-08-19	6525.00	1	2025-08-03 19:56:38.109221	2025-08-03 19:56:38.109221	0.50	3262.50
524	\N	60	2024-08-19	5830.00	1	2025-08-03 19:56:38.392712	2025-08-03 19:56:38.392712	0.65	3789.50
525	\N	44	2024-08-20	6765.00	1	2025-08-03 19:56:38.661781	2025-08-03 19:56:38.661781	0.46	3121.00
526	\N	44	2024-08-20	5770.00	1	2025-08-03 19:56:38.943753	2025-08-03 19:56:38.943753	0.45	2620.68
527	\N	44	2024-08-20	14665.00	1	2025-08-03 19:56:39.201009	2025-08-03 19:56:39.201009	0.44	6500.00
528	\N	44	2024-08-20	7565.00	1	2025-08-03 19:56:39.437787	2025-08-03 19:56:39.437787	0.60	4539.00
529	\N	138	2024-08-20	1885.00	1	2025-08-03 19:56:39.973194	2025-08-03 19:56:39.973194	0.50	940.00
530	\N	65	2024-08-20	6605.00	1	2025-08-03 19:56:40.190832	2025-08-03 19:56:40.190832	0.50	3302.50
531	\N	57	2024-08-20	1100.00	1	2025-08-03 19:56:40.550546	2025-08-03 19:56:40.550546	0.64	700.00
532	\N	57	2024-08-20	1100.00	1	2025-08-03 19:56:40.782725	2025-08-03 19:56:40.782725	0.64	700.00
533	\N	60	2024-08-20	3460.00	1	2025-08-03 19:56:41.042843	2025-08-03 19:56:41.042843	0.50	1730.00
534	\N	44	2024-08-21	6655.00	1	2025-08-03 19:56:41.323121	2025-08-03 19:56:41.323121	0.28	1886.34
535	\N	44	2024-08-21	8580.00	1	2025-08-03 19:56:41.60191	2025-08-03 19:56:41.60191	0.70	6006.00
536	\N	44	2024-08-21	8590.00	1	2025-08-03 19:56:41.875168	2025-08-03 19:56:41.875168	0.79	6801.93
537	\N	44	2024-08-21	10110.00	1	2025-08-03 19:56:42.147107	2025-08-03 19:56:42.147107	0.70	7031.66
538	\N	44	2024-08-21	6510.00	1	2025-08-03 19:56:42.420428	2025-08-03 19:56:42.420428	0.60	3906.00
539	\N	44	2024-08-21	4500.00	1	2025-08-03 19:56:42.686987	2025-08-03 19:56:42.686987	0.31	1383.43
540	\N	44	2024-08-21	6380.00	1	2025-08-03 19:56:42.958322	2025-08-03 19:56:42.958322	0.60	3835.20
541	\N	48	2024-08-21	4430.00	1	2025-08-03 19:56:43.239257	2025-08-03 19:56:43.239257	0.50	2215.00
542	\N	139	2024-08-21	1350.00	1	2025-08-03 19:56:43.693161	2025-08-03 19:56:43.693161	0.70	945.00
543	\N	55	2024-08-21	8000.00	1	2025-08-03 19:56:44.108378	2025-08-03 19:56:44.108378	0.45	3600.00
544	\N	55	2024-08-21	6410.00	1	2025-08-03 19:56:44.390222	2025-08-03 19:56:44.390222	0.45	2884.50
545	\N	53	2024-08-21	11710.00	1	2025-08-03 19:56:44.755217	2025-08-03 19:56:44.755217	0.43	5000.00
546	\N	44	2024-08-22	13140.00	1	2025-08-03 19:56:45.05138	2025-08-03 19:56:45.05138	0.49	6383.04
547	\N	44	2024-08-22	6430.00	1	2025-08-03 19:56:45.437856	2025-08-03 19:56:45.437856	0.37	2394.00
548	\N	44	2024-08-22	4715.00	1	2025-08-03 19:56:45.698474	2025-08-03 19:56:45.698474	0.23	1079.52
549	\N	45	2024-08-22	7788.20	1	2025-08-03 19:56:46.025542	2025-08-03 19:56:46.025542	0.50	3894.10
550	\N	80	2024-08-22	3255.00	1	2025-08-03 19:56:46.285574	2025-08-03 19:56:46.285574	0.80	2604.00
551	\N	83	2024-08-22	4920.00	1	2025-08-03 19:56:46.511067	2025-08-03 19:56:46.511067	0.40	1968.00
552	\N	55	2024-08-22	5250.00	1	2025-08-03 19:56:46.786242	2025-08-03 19:56:46.786242	0.40	2078.67
553	\N	116	2024-08-22	2270.00	1	2025-08-03 19:56:47.049382	2025-08-03 19:56:47.049382	0.50	1139.15
554	\N	43	2024-08-23	8405.00	1	2025-08-03 19:56:47.35456	2025-08-03 19:56:47.35456	0.50	4202.50
555	\N	43	2024-08-23	4525.00	1	2025-08-03 19:56:47.642959	2025-08-03 19:56:47.642959	0.65	2940.00
556	\N	44	2024-08-23	1490.00	1	2025-08-03 19:56:47.913898	2025-08-03 19:56:47.913898	0.49	731.33
557	\N	44	2024-08-23	3480.00	1	2025-08-03 19:56:48.181699	2025-08-03 19:56:48.181699	0.33	1158.67
558	\N	44	2024-08-23	10345.00	1	2025-08-03 19:56:48.460285	2025-08-03 19:56:48.460285	0.70	7241.50
559	\N	44	2024-08-23	7310.00	1	2025-08-03 19:56:48.740044	2025-08-03 19:56:48.740044	0.70	5117.00
560	\N	45	2024-08-23	7835.00	1	2025-08-03 19:56:48.982272	2025-08-03 19:56:48.982272	0.50	3917.50
561	\N	83	2024-08-23	10770.00	1	2025-08-03 19:56:49.251191	2025-08-03 19:56:49.251191	0.37	4000.00
562	\N	116	2024-08-23	2915.00	1	2025-08-03 19:56:49.524138	2025-08-03 19:56:49.524138	0.50	1457.50
563	\N	44	2024-08-26	8530.00	1	2025-08-03 19:56:49.786895	2025-08-03 19:56:49.786895	0.70	5971.00
564	\N	44	2024-08-26	6660.00	1	2025-08-03 19:56:50.048894	2025-08-03 19:56:50.048894	0.62	4160.00
565	\N	44	2024-08-26	4900.00	1	2025-08-03 19:56:50.314367	2025-08-03 19:56:50.314367	0.58	2840.00
566	\N	44	2024-08-26	7600.00	1	2025-08-03 19:56:50.560161	2025-08-03 19:56:50.560161	0.42	3166.35
567	\N	44	2024-08-26	6520.00	1	2025-08-03 19:56:50.828376	2025-08-03 19:56:50.828376	0.36	2324.33
568	\N	86	2024-08-26	9455.00	1	2025-08-03 19:56:51.106718	2025-08-03 19:56:51.106718	0.50	4727.50
569	\N	60	2024-08-26	1960.00	1	2025-08-03 19:56:51.340316	2025-08-03 19:56:51.340316	0.80	1568.00
570	\N	44	2024-08-27	6985.00	1	2025-08-03 19:56:51.608652	2025-08-03 19:56:51.608652	0.34	2355.60
571	\N	44	2024-08-27	11530.00	1	2025-08-03 19:56:51.879841	2025-08-03 19:56:51.879841	0.65	7504.28
572	\N	44	2024-08-27	7530.00	1	2025-08-03 19:56:52.145009	2025-08-03 19:56:52.145009	0.70	5271.00
573	\N	140	2024-08-27	8505.00	1	2025-08-03 19:56:52.614946	2025-08-03 19:56:52.614946	0.50	4252.50
574	\N	124	2024-08-27	6040.00	1	2025-08-03 19:56:52.890148	2025-08-03 19:56:52.890148	0.60	3624.00
575	\N	55	2024-08-27	2805.00	1	2025-08-03 19:56:53.112333	2025-08-03 19:56:53.112333	0.45	1272.52
576	\N	57	2024-08-27	8310.00	1	2025-08-03 19:56:53.390176	2025-08-03 19:56:53.390176	0.54	4510.00
577	\N	44	2024-08-28	7385.00	1	2025-08-03 19:56:53.660811	2025-08-03 19:56:53.660811	0.55	4035.33
578	\N	94	2024-08-28	14505.00	1	2025-08-03 19:56:53.92986	2025-08-03 19:56:53.92986	0.48	7005.00
579	\N	80	2024-08-28	4685.00	1	2025-08-03 19:56:54.195648	2025-08-03 19:56:54.195648	0.75	3513.75
580	\N	80	2024-08-28	11455.00	1	2025-08-03 19:56:54.42325	2025-08-03 19:56:54.42325	0.80	9164.00
581	\N	141	2024-08-28	14875.00	1	2025-08-03 19:56:54.904277	2025-08-03 19:56:54.904277	0.50	7437.50
582	\N	55	2024-08-28	8155.00	1	2025-08-03 19:56:55.170599	2025-08-03 19:56:55.170599	0.36	2958.34
583	\N	55	2024-08-28	7475.00	1	2025-08-03 19:56:55.439198	2025-08-03 19:56:55.439198	0.74	5524.76
584	\N	55	2024-08-28	6310.00	1	2025-08-03 19:56:55.81524	2025-08-03 19:56:55.81524	0.52	3306.87
585	\N	108	2024-08-28	14115.00	1	2025-08-03 19:56:56.083251	2025-08-03 19:56:56.083251	0.40	5636.00
586	\N	142	2024-08-28	5150.00	1	2025-08-03 19:56:56.659826	2025-08-03 19:56:56.659826	0.50	2575.00
587	\N	44	2024-08-29	2915.00	1	2025-08-03 19:56:56.944826	2025-08-03 19:56:56.944826	0.70	2040.50
588	\N	44	2024-08-29	10615.00	1	2025-08-03 19:56:57.16439	2025-08-03 19:56:57.16439	0.48	5138.64
589	\N	44	2024-08-29	5510.00	1	2025-08-03 19:56:57.439365	2025-08-03 19:56:57.439365	0.32	1776.49
590	\N	81	2024-08-29	8550.00	1	2025-08-03 19:56:57.813587	2025-08-03 19:56:57.813587	0.50	4275.00
591	\N	81	2024-08-29	6470.00	1	2025-08-03 19:56:58.19845	2025-08-03 19:56:58.19845	0.50	3235.00
592	\N	81	2024-08-29	6500.00	1	2025-08-03 19:56:58.48315	2025-08-03 19:56:58.48315	0.50	3250.00
593	\N	81	2024-08-29	8930.00	1	2025-08-03 19:56:58.781214	2025-08-03 19:56:58.781214	0.50	4465.00
594	\N	55	2024-08-29	6375.00	1	2025-08-03 19:56:59.14615	2025-08-03 19:56:59.14615	0.43	2720.00
595	\N	55	2024-08-29	9560.00	1	2025-08-03 19:56:59.438776	2025-08-03 19:56:59.438776	0.36	3445.78
596	\N	102	2024-08-29	8760.00	1	2025-08-03 19:56:59.709484	2025-08-03 19:56:59.709484	0.70	6132.00
597	\N	116	2024-08-29	8770.00	1	2025-08-03 19:56:59.942221	2025-08-03 19:56:59.942221	0.50	4385.00
598	\N	116	2024-08-29	5860.00	1	2025-08-03 19:57:00.182391	2025-08-03 19:57:00.182391	0.50	2930.00
599	\N	130	2024-08-30	1550.00	1	2025-08-03 19:57:00.454579	2025-08-03 19:57:00.454579	0.83	1293.50
600	\N	130	2024-08-30	1990.00	1	2025-08-03 19:57:00.794942	2025-08-03 19:57:00.794942	0.65	1293.50
601	\N	44	2024-08-30	4135.00	1	2025-08-03 19:57:01.071947	2025-08-03 19:57:01.071947	0.70	2894.50
602	\N	44	2024-08-30	2205.00	1	2025-08-03 19:57:01.313937	2025-08-03 19:57:01.313937	0.98	2166.66
603	\N	80	2024-08-30	9565.00	1	2025-08-03 19:57:01.600422	2025-08-03 19:57:01.600422	0.60	5739.00
604	\N	143	2024-08-30	5530.00	1	2025-08-03 19:57:02.070782	2025-08-03 19:57:02.070782	0.50	2765.00
605	\N	53	2024-08-30	8105.00	1	2025-08-03 19:57:02.356942	2025-08-03 19:57:02.356942	0.59	4800.00
606	\N	44	2024-09-03	6980.00	1	2025-08-03 19:57:02.657804	2025-08-03 19:57:02.657804	0.68	4780.00
607	\N	44	2024-09-03	1705.00	1	2025-08-03 19:57:02.976434	2025-08-03 19:57:02.976434	0.70	1193.50
608	\N	88	2024-09-03	4780.00	1	2025-08-03 19:57:03.269155	2025-08-03 19:57:03.269155	0.57	2735.69
609	\N	120	2024-09-03	4710.00	1	2025-08-03 19:57:03.55272	2025-08-03 19:57:03.55272	0.50	2355.00
610	\N	55	2024-09-03	5570.00	1	2025-08-03 19:57:03.848986	2025-08-03 19:57:03.848986	0.35	1949.50
611	\N	53	2024-09-03	3245.00	1	2025-08-03 19:57:04.190883	2025-08-03 19:57:04.190883	0.62	2000.00
612	\N	53	2024-09-03	7430.00	1	2025-08-03 19:57:04.48391	2025-08-03 19:57:04.48391	0.67	5000.00
613	\N	53	2024-09-03	7370.00	1	2025-08-03 19:57:04.781332	2025-08-03 19:57:04.781332	0.65	4800.00
614	\N	53	2024-09-03	7475.00	1	2025-08-03 19:57:05.060343	2025-08-03 19:57:05.060343	0.60	4500.00
615	\N	53	2024-09-03	9950.00	1	2025-08-03 19:57:05.34217	2025-08-03 19:57:05.34217	0.55	5500.00
616	\N	44	2024-09-04	6065.00	1	2025-08-03 19:57:05.787543	2025-08-03 19:57:05.787543	0.36	2211.00
617	\N	44	2024-09-04	9495.00	1	2025-08-03 19:57:06.296977	2025-08-03 19:57:06.296977	0.45	4245.28
618	\N	44	2024-09-04	6315.00	1	2025-08-03 19:57:06.59389	2025-08-03 19:57:06.59389	0.97	6099.32
619	\N	44	2024-09-04	8685.00	1	2025-08-03 19:57:06.889422	2025-08-03 19:57:06.889422	0.38	3282.00
620	\N	144	2024-09-04	9815.00	1	2025-08-03 19:57:07.29313	2025-08-03 19:57:07.29313	0.60	5889.00
621	\N	48	2024-09-04	5540.00	1	2025-08-03 19:57:07.536964	2025-08-03 19:57:07.536964	0.60	3300.00
622	\N	102	2024-09-04	4330.00	1	2025-08-03 19:57:07.815429	2025-08-03 19:57:07.815429	0.60	2598.00
623	\N	52	2024-09-04	8410.00	1	2025-08-03 19:57:08.065982	2025-08-03 19:57:08.065982	0.50	4205.00
624	\N	53	2024-09-04	4910.00	1	2025-08-03 19:57:08.325972	2025-08-03 19:57:08.325972	0.43	2100.00
625	\N	44	2024-09-05	8725.80	1	2025-08-03 19:57:08.591466	2025-08-03 19:57:08.591466	0.70	6090.00
626	\N	44	2024-09-05	6290.00	1	2025-08-03 19:57:08.860497	2025-08-03 19:57:08.860497	0.42	2666.82
627	\N	44	2024-09-05	8115.00	1	2025-08-03 19:57:09.202	2025-08-03 19:57:09.202	0.39	3160.33
628	\N	80	2024-09-05	550.00	1	2025-08-03 19:57:09.418317	2025-08-03 19:57:09.418317	0.50	275.00
629	\N	80	2024-09-05	8175.00	1	2025-08-03 19:57:09.708849	2025-08-03 19:57:09.708849	0.64	5255.25
630	\N	80	2024-09-05	5989.20	1	2025-08-03 19:57:09.934065	2025-08-03 19:57:09.934065	0.64	3854.50
631	\N	82	2024-09-05	7140.00	1	2025-08-03 19:57:10.163465	2025-08-03 19:57:10.163465	0.50	3570.00
632	\N	48	2024-09-05	4675.00	1	2025-08-03 19:57:10.389509	2025-08-03 19:57:10.389509	0.50	2325.00
633	\N	44	2024-09-06	3140.00	1	2025-08-03 19:57:10.658183	2025-08-03 19:57:10.658183	0.60	1878.63
634	\N	44	2024-09-06	6565.00	1	2025-08-03 19:57:10.885948	2025-08-03 19:57:10.885948	0.57	3757.66
635	\N	44	2024-09-06	8540.00	1	2025-08-03 19:57:11.165479	2025-08-03 19:57:11.165479	0.55	4678.63
636	\N	44	2024-09-06	8840.00	1	2025-08-03 19:57:11.437133	2025-08-03 19:57:11.437133	0.60	5304.00
637	\N	44	2024-09-06	6960.00	1	2025-08-03 19:57:11.703771	2025-08-03 19:57:11.703771	0.61	4253.33
638	\N	80	2024-09-06	4407.00	1	2025-08-03 19:57:11.980159	2025-08-03 19:57:11.980159	0.36	1582.20
639	\N	145	2024-09-06	5465.00	1	2025-08-03 19:57:12.412614	2025-08-03 19:57:12.412614	0.50	2732.50
640	\N	52	2024-09-06	1100.00	1	2025-08-03 19:57:12.685526	2025-08-03 19:57:12.685526	0.50	550.00
641	\N	116	2024-09-06	2870.00	1	2025-08-03 19:57:12.950725	2025-08-03 19:57:12.950725	0.61	1758.50
642	\N	57	2024-09-06	9435.00	1	2025-08-03 19:57:13.228361	2025-08-03 19:57:13.228361	0.50	4735.00
643	\N	146	2024-09-09	9390.00	1	2025-08-03 19:57:13.69676	2025-08-03 19:57:13.69676	0.60	5634.00
644	\N	48	2024-09-09	3650.00	1	2025-08-03 19:57:13.911117	2025-08-03 19:57:13.911117	0.63	2300.00
645	\N	48	2024-09-09	5580.00	1	2025-08-03 19:57:14.182176	2025-08-03 19:57:14.182176	0.59	3300.00
646	\N	116	2024-09-09	8495.00	1	2025-08-03 19:57:14.409591	2025-08-03 19:57:14.409591	0.43	3625.00
647	\N	129	2024-09-09	13590.00	1	2025-08-03 19:57:14.688232	2025-08-03 19:57:14.688232	0.65	8833.50
648	\N	43	2024-09-10	3310.00	1	2025-08-03 19:57:14.904857	2025-08-03 19:57:14.904857	0.62	2050.00
649	\N	43	2024-09-10	7885.00	1	2025-08-03 19:57:15.13123	2025-08-03 19:57:15.13123	0.45	3525.00
650	\N	43	2024-09-10	7815.00	1	2025-08-03 19:57:15.39835	2025-08-03 19:57:15.39835	0.50	3875.00
651	\N	44	2024-09-10	2730.00	1	2025-08-03 19:57:15.672152	2025-08-03 19:57:15.672152	0.67	1830.00
652	\N	44	2024-09-10	6205.00	1	2025-08-03 19:57:15.940499	2025-08-03 19:57:15.940499	0.62	3848.24
653	\N	44	2024-09-10	4980.00	1	2025-08-03 19:57:16.207553	2025-08-03 19:57:16.207553	0.67	3330.00
654	\N	66	2024-09-10	2945.00	1	2025-08-03 19:57:16.484112	2025-08-03 19:57:16.484112	0.60	1767.00
655	\N	145	2024-09-10	6110.00	1	2025-08-03 19:57:16.754948	2025-08-03 19:57:16.754948	0.72	4378.41
656	\N	102	2024-09-10	2090.00	1	2025-08-03 19:57:17.021298	2025-08-03 19:57:17.021298	0.50	1045.00
657	\N	57	2024-09-10	2725.00	1	2025-08-03 19:57:17.30035	2025-08-03 19:57:17.30035	0.67	1825.00
658	\N	44	2024-09-11	8885.00	1	2025-08-03 19:57:17.595983	2025-08-03 19:57:17.595983	0.49	4397.66
659	\N	44	2024-09-11	1315.00	1	2025-08-03 19:57:17.87986	2025-08-03 19:57:17.87986	0.49	638.33
660	\N	44	2024-09-11	7045.00	1	2025-08-03 19:57:18.148402	2025-08-03 19:57:18.148402	0.41	2898.33
661	\N	44	2024-09-11	7525.00	1	2025-08-03 19:57:18.418915	2025-08-03 19:57:18.418915	0.70	5267.50
662	\N	147	2024-09-11	2127.24	1	2025-08-03 19:57:18.896751	2025-08-03 19:57:18.896751	0.50	1065.00
663	\N	45	2024-09-11	7170.00	1	2025-08-03 19:57:19.163803	2025-08-03 19:57:19.163803	0.50	3585.00
664	\N	45	2024-09-11	6665.00	1	2025-08-03 19:57:19.435024	2025-08-03 19:57:19.435024	0.45	3000.00
665	\N	85	2024-09-11	12895.00	1	2025-08-03 19:57:19.71238	2025-08-03 19:57:19.71238	0.46	5947.50
666	\N	97	2024-09-11	8280.00	1	2025-08-03 19:57:19.988926	2025-08-03 19:57:19.988926	0.21	1720.36
667	\N	80	2024-09-11	8700.00	1	2025-08-03 19:57:20.225814	2025-08-03 19:57:20.225814	0.60	5220.00
668	\N	104	2024-09-11	9125.00	1	2025-08-03 19:57:20.497921	2025-08-03 19:57:20.497921	0.20	1825.00
669	\N	104	2024-09-11	2895.00	1	2025-08-03 19:57:20.717462	2025-08-03 19:57:20.717462	0.50	1447.50
670	\N	104	2024-09-11	9390.00	1	2025-08-03 19:57:20.991515	2025-08-03 19:57:20.991515	0.65	6103.50
671	\N	148	2024-09-11	2985.00	1	2025-08-03 19:57:21.462656	2025-08-03 19:57:21.462656	0.37	1094.25
672	\N	55	2024-09-11	5895.00	1	2025-08-03 19:57:21.698919	2025-08-03 19:57:21.698919	0.35	2063.25
673	\N	84	2024-09-11	3545.00	1	2025-08-03 19:57:21.95566	2025-08-03 19:57:21.95566	0.79	2800.00
674	\N	110	2024-09-11	6275.00	1	2025-08-03 19:57:22.228256	2025-08-03 19:57:22.228256	0.50	3137.50
675	\N	52	2024-09-11	2445.00	1	2025-08-03 19:57:22.492251	2025-08-03 19:57:22.492251	0.50	1222.50
676	\N	60	2024-09-11	4810.00	1	2025-08-03 19:57:22.76878	2025-08-03 19:57:22.76878	0.56	2709.00
677	\N	60	2024-09-11	6440.00	1	2025-08-03 19:57:23.052224	2025-08-03 19:57:23.052224	0.72	4636.80
678	\N	44	2024-09-12	7200.00	1	2025-08-03 19:57:23.322499	2025-08-03 19:57:23.322499	0.57	4087.66
679	\N	44	2024-09-12	6375.00	1	2025-08-03 19:57:23.600115	2025-08-03 19:57:23.600115	0.36	2282.81
680	\N	110	2024-09-12	6285.00	1	2025-08-03 19:57:23.871375	2025-08-03 19:57:23.871375	0.50	3142.50
681	\N	110	2024-09-12	5250.00	1	2025-08-03 19:57:24.139873	2025-08-03 19:57:24.139873	0.50	2625.00
682	\N	110	2024-09-12	10975.00	1	2025-08-03 19:57:24.408307	2025-08-03 19:57:24.408307	0.60	6546.00
683	\N	116	2024-09-12	7695.00	1	2025-08-03 19:57:24.688546	2025-08-03 19:57:24.688546	0.51	3924.25
684	\N	116	2024-09-12	6155.00	1	2025-08-03 19:57:24.930923	2025-08-03 19:57:24.930923	0.11	670.67
685	\N	60	2024-09-12	4615.00	1	2025-08-03 19:57:25.145101	2025-08-03 19:57:25.145101	0.66	3065.25
686	\N	53	2024-09-12	2045.00	1	2025-08-03 19:57:25.369858	2025-08-03 19:57:25.369858	0.73	1500.00
687	\N	53	2024-09-12	2365.00	1	2025-08-03 19:57:25.656767	2025-08-03 19:57:25.656767	0.80	1900.00
688	\N	43	2024-09-13	5785.00	1	2025-08-03 19:57:26.034525	2025-08-03 19:57:26.034525	0.57	3300.00
689	\N	43	2024-09-13	7490.00	1	2025-08-03 19:57:26.303005	2025-08-03 19:57:26.303005	0.59	4400.00
690	\N	44	2024-09-13	4375.00	1	2025-08-03 19:57:26.582994	2025-08-03 19:57:26.582994	0.48	2117.50
691	\N	44	2024-09-13	8020.00	1	2025-08-03 19:57:26.880064	2025-08-03 19:57:26.880064	0.50	4010.00
692	\N	44	2024-09-13	9410.00	1	2025-08-03 19:57:27.116463	2025-08-03 19:57:27.116463	0.60	5686.00
693	\N	44	2024-09-13	2400.00	1	2025-08-03 19:57:27.393632	2025-08-03 19:57:27.393632	0.28	680.00
694	\N	44	2024-09-13	7740.00	1	2025-08-03 19:57:27.674347	2025-08-03 19:57:27.674347	0.70	5418.00
695	\N	44	2024-09-13	8275.00	1	2025-08-03 19:57:27.957917	2025-08-03 19:57:27.957917	0.50	4129.67
696	\N	44	2024-09-13	8750.00	1	2025-08-03 19:57:28.441789	2025-08-03 19:57:28.441789	0.70	6100.00
697	\N	44	2024-09-13	8310.00	1	2025-08-03 19:57:28.677998	2025-08-03 19:57:28.677998	0.22	1867.00
698	\N	45	2024-09-13	8225.00	1	2025-08-03 19:57:28.93349	2025-08-03 19:57:28.93349	0.49	4000.00
699	\N	116	2024-09-13	5360.00	1	2025-08-03 19:57:29.266357	2025-08-03 19:57:29.266357	0.50	2680.00
700	\N	44	2024-09-16	6465.00	1	2025-08-03 19:57:29.537819	2025-08-03 19:57:29.537819	0.70	4525.50
701	\N	44	2024-09-16	8095.00	1	2025-08-03 19:57:29.818386	2025-08-03 19:57:29.818386	0.38	3100.64
702	\N	44	2024-09-16	8215.00	1	2025-08-03 19:57:30.082971	2025-08-03 19:57:30.082971	0.70	5750.50
703	\N	44	2024-09-16	7715.00	1	2025-08-03 19:57:30.360629	2025-08-03 19:57:30.360629	0.70	5400.50
704	\N	149	2024-09-16	7005.00	1	2025-08-03 19:57:30.838478	2025-08-03 19:57:30.838478	0.60	4203.00
705	\N	89	2024-09-16	12295.00	1	2025-08-03 19:57:31.068725	2025-08-03 19:57:31.068725	0.66	8092.00
706	\N	83	2024-09-16	1425.00	1	2025-08-03 19:57:31.286879	2025-08-03 19:57:31.286879	0.50	712.50
707	\N	44	2024-09-17	5270.00	1	2025-08-03 19:57:31.550329	2025-08-03 19:57:31.550329	0.84	4408.51
708	\N	44	2024-09-17	7200.00	1	2025-08-03 19:57:31.81872	2025-08-03 19:57:31.81872	0.54	3870.00
709	\N	150	2024-09-17	2140.00	1	2025-08-03 19:57:32.271163	2025-08-03 19:57:32.271163	0.50	1070.00
710	\N	104	2024-09-17	2050.00	1	2025-08-03 19:57:32.544925	2025-08-03 19:57:32.544925	0.50	1025.00
711	\N	58	2024-09-17	3470.00	1	2025-08-03 19:57:32.787323	2025-08-03 19:57:32.787323	0.81	2800.00
712	\N	83	2024-09-17	6705.00	1	2025-08-03 19:57:33.055056	2025-08-03 19:57:33.055056	0.50	3352.50
713	\N	55	2024-09-17	2050.00	1	2025-08-03 19:57:33.379568	2025-08-03 19:57:33.379568	0.25	512.50
714	\N	55	2024-09-17	6480.00	1	2025-08-03 19:57:33.657885	2025-08-03 19:57:33.657885	0.40	2592.00
715	\N	55	2024-09-17	5640.00	1	2025-08-03 19:57:33.931824	2025-08-03 19:57:33.931824	0.42	2388.74
716	\N	52	2024-09-17	5395.00	1	2025-08-03 19:57:34.193735	2025-08-03 19:57:34.193735	0.50	2697.50
717	\N	52	2024-09-17	6555.00	1	2025-08-03 19:57:34.570804	2025-08-03 19:57:34.570804	0.50	3277.50
718	\N	116	2024-09-17	5215.00	1	2025-08-03 19:57:34.844467	2025-08-03 19:57:34.844467	0.48	2500.00
719	\N	116	2024-09-17	9745.00	1	2025-08-03 19:57:35.115774	2025-08-03 19:57:35.115774	0.45	4405.50
720	\N	116	2024-09-17	3225.00	1	2025-08-03 19:57:35.349082	2025-08-03 19:57:35.349082	0.47	1500.00
721	\N	57	2024-09-17	840.00	1	2025-08-03 19:57:35.637653	2025-08-03 19:57:35.637653	0.50	420.00
722	\N	57	2024-09-17	3095.00	1	2025-08-03 19:57:35.916382	2025-08-03 19:57:35.916382	0.61	1895.00
723	\N	60	2024-09-17	6260.00	1	2025-08-03 19:57:36.181136	2025-08-03 19:57:36.181136	0.75	4695.00
724	\N	45	2024-09-18	11495.00	1	2025-08-03 19:57:36.449558	2025-08-03 19:57:36.449558	0.50	5747.50
725	\N	89	2024-09-18	12625.00	1	2025-08-03 19:57:36.684176	2025-08-03 19:57:36.684176	0.55	7000.00
726	\N	52	2024-09-18	4321.25	1	2025-08-03 19:57:37.004313	2025-08-03 19:57:37.004313	0.50	2161.00
727	\N	116	2024-09-18	3825.00	1	2025-08-03 19:57:37.270397	2025-08-03 19:57:37.270397	0.45	1721.25
728	\N	126	2024-09-18	10845.00	1	2025-08-03 19:57:37.537972	2025-08-03 19:57:37.537972	0.50	5425.00
729	\N	53	2024-09-18	13865.00	1	2025-08-03 19:57:37.911807	2025-08-03 19:57:37.911807	0.60	8250.00
730	\N	44	2024-09-19	8435.00	1	2025-08-03 19:57:38.133952	2025-08-03 19:57:38.133952	0.47	3945.65
731	\N	44	2024-09-19	2315.00	1	2025-08-03 19:57:38.388355	2025-08-03 19:57:38.388355	0.48	1105.00
732	\N	44	2024-09-19	11510.00	1	2025-08-03 19:57:38.750215	2025-08-03 19:57:38.750215	0.40	4563.84
733	\N	45	2024-09-19	4320.00	1	2025-08-03 19:57:39.01936	2025-08-03 19:57:39.01936	0.50	2160.00
734	\N	89	2024-09-19	12500.00	1	2025-08-03 19:57:39.375923	2025-08-03 19:57:39.375923	0.54	6700.00
735	\N	65	2024-09-19	4995.00	1	2025-08-03 19:57:39.643962	2025-08-03 19:57:39.643962	0.55	2747.25
736	\N	132	2024-09-19	7685.00	1	2025-08-03 19:57:39.92105	2025-08-03 19:57:39.92105	0.50	3842.50
737	\N	132	2024-09-19	8765.00	1	2025-08-03 19:57:40.164135	2025-08-03 19:57:40.164135	0.40	3506.00
738	\N	84	2024-09-20	9720.00	1	2025-08-03 19:57:40.425618	2025-08-03 19:57:40.425618	0.72	6975.00
739	\N	116	2024-09-20	1450.00	1	2025-08-03 19:57:40.66246	2025-08-03 19:57:40.66246	0.55	797.50
740	\N	116	2024-09-20	8715.00	1	2025-08-03 19:57:41.038324	2025-08-03 19:57:41.038324	0.55	4793.25
741	\N	44	2024-09-23	8355.00	1	2025-08-03 19:57:41.319233	2025-08-03 19:57:41.319233	0.20	1712.66
742	\N	44	2024-09-23	3625.00	1	2025-08-03 19:57:41.59742	2025-08-03 19:57:41.59742	0.21	773.44
743	\N	44	2024-09-23	2125.00	1	2025-08-03 19:57:41.858995	2025-08-03 19:57:41.858995	0.70	1487.50
744	\N	44	2024-09-23	1620.00	1	2025-08-03 19:57:42.125671	2025-08-03 19:57:42.125671	1.00	1620.00
745	\N	44	2024-09-23	5885.00	1	2025-08-03 19:57:42.389648	2025-08-03 19:57:42.389648	0.42	2493.33
746	\N	124	2024-09-23	2095.00	1	2025-08-03 19:57:42.660225	2025-08-03 19:57:42.660225	0.70	1466.50
747	\N	55	2024-09-23	5270.00	1	2025-08-03 19:57:42.926789	2025-08-03 19:57:42.926789	0.43	2258.59
748	\N	52	2024-09-23	4855.00	1	2025-08-03 19:57:43.219687	2025-08-03 19:57:43.219687	0.60	2913.00
749	\N	116	2024-09-23	9690.00	1	2025-08-03 19:57:43.49634	2025-08-03 19:57:43.49634	0.60	5814.00
750	\N	60	2024-09-23	4855.00	1	2025-08-03 19:57:43.762292	2025-08-03 19:57:43.762292	0.49	2403.00
751	\N	60	2024-09-23	5305.00	1	2025-08-03 19:57:44.028384	2025-08-03 19:57:44.028384	0.70	3713.50
752	\N	44	2024-09-24	3820.00	1	2025-08-03 19:57:44.398683	2025-08-03 19:57:44.398683	0.41	1562.00
753	\N	45	2024-09-24	5315.00	1	2025-08-03 19:57:44.754564	2025-08-03 19:57:44.754564	0.50	2657.50
754	\N	45	2024-09-24	8260.00	1	2025-08-03 19:57:45.026198	2025-08-03 19:57:45.026198	0.50	4130.00
755	\N	151	2024-09-24	7180.00	1	2025-08-03 19:57:45.544767	2025-08-03 19:57:45.544767	0.34	2444.07
756	\N	151	2024-09-24	6125.00	1	2025-08-03 19:57:45.77559	2025-08-03 19:57:45.77559	0.34	2084.95
757	\N	152	2024-09-24	14795.00	1	2025-08-03 19:57:46.228231	2025-08-03 19:57:46.228231	0.50	7397.50
758	\N	86	2024-09-24	7880.00	1	2025-08-03 19:57:46.46086	2025-08-03 19:57:46.46086	0.60	4728.00
759	\N	55	2024-09-24	4270.00	1	2025-08-03 19:57:46.713143	2025-08-03 19:57:46.713143	0.36	1544.18
760	\N	84	2024-09-24	10210.00	1	2025-08-03 19:57:46.980388	2025-08-03 19:57:46.980388	0.31	3200.00
761	\N	153	2024-09-24	6323.00	1	2025-08-03 19:57:47.388761	2025-08-03 19:57:47.388761	0.38	2414.18
762	\N	110	2024-09-24	9315.00	1	2025-08-03 19:57:47.711	2025-08-03 19:57:47.711	0.50	4617.50
763	\N	52	2024-09-24	4457.62	1	2025-08-03 19:57:47.949604	2025-08-03 19:57:47.949604	0.50	2229.00
764	\N	44	2024-09-25	9215.00	1	2025-08-03 19:57:48.326791	2025-08-03 19:57:48.326791	0.32	2922.33
765	\N	44	2024-09-25	10219.52	1	2025-08-03 19:57:48.708539	2025-08-03 19:57:48.708539	0.70	7153.66
766	\N	44	2024-09-25	5606.45	1	2025-08-03 19:57:48.934497	2025-08-03 19:57:48.934497	0.38	2145.29
767	\N	55	2024-09-25	2200.00	1	2025-08-03 19:57:49.214929	2025-08-03 19:57:49.214929	0.36	787.87
768	\N	102	2024-09-25	1385.00	1	2025-08-03 19:57:49.482377	2025-08-03 19:57:49.482377	0.50	692.50
769	\N	108	2024-09-25	8735.09	1	2025-08-03 19:57:49.749734	2025-08-03 19:57:49.749734	0.35	3057.28
770	\N	108	2024-09-25	8735.09	1	2025-08-03 19:57:50.007209	2025-08-03 19:57:50.007209	0.35	3057.28
771	\N	116	2024-09-25	10500.00	1	2025-08-03 19:57:50.280288	2025-08-03 19:57:50.280288	0.60	6300.00
772	\N	53	2024-09-25	8030.00	1	2025-08-03 19:57:50.494809	2025-08-03 19:57:50.494809	0.60	4800.00
773	\N	44	2024-09-26	7060.00	1	2025-08-03 19:57:50.765573	2025-08-03 19:57:50.765573	0.70	4942.00
774	\N	88	2024-09-26	1275.00	1	2025-08-03 19:57:51.034218	2025-08-03 19:57:51.034218	0.56	714.00
775	\N	48	2024-09-26	2805.94	1	2025-08-03 19:57:51.287288	2025-08-03 19:57:51.287288	0.71	2000.00
776	\N	48	2024-09-26	7305.00	1	2025-08-03 19:57:51.546577	2025-08-03 19:57:51.546577	0.60	4383.00
777	\N	48	2024-09-26	15850.00	1	2025-08-03 19:57:51.774199	2025-08-03 19:57:51.774199	0.63	10000.00
778	\N	154	2024-09-26	10625.00	1	2025-08-03 19:57:52.231605	2025-08-03 19:57:52.231605	0.89	9500.00
779	\N	44	2024-09-27	4315.00	1	2025-08-03 19:57:52.45384	2025-08-03 19:57:52.45384	0.50	2157.50
780	\N	44	2024-09-27	3455.00	1	2025-08-03 19:57:52.726305	2025-08-03 19:57:52.726305	0.70	2418.50
781	\N	44	2024-09-27	5740.00	1	2025-08-03 19:57:52.987293	2025-08-03 19:57:52.987293	0.70	4018.00
782	\N	44	2024-09-27	3200.00	1	2025-08-03 19:57:53.252999	2025-08-03 19:57:53.252999	0.70	2240.00
783	\N	44	2024-09-27	8560.00	1	2025-08-03 19:57:53.522531	2025-08-03 19:57:53.522531	0.27	2343.04
784	\N	155	2024-09-27	4410.00	1	2025-08-03 19:57:53.988033	2025-08-03 19:57:53.988033	0.50	2221.35
785	\N	131	2024-09-27	4200.00	1	2025-08-03 19:57:54.360244	2025-08-03 19:57:54.360244	0.58	2436.00
786	\N	52	2024-09-27	4224.30	1	2025-08-03 19:57:54.619959	2025-08-03 19:57:54.619959	0.50	2113.00
787	\N	52	2024-09-27	15525.00	1	2025-08-03 19:57:54.882699	2025-08-03 19:57:54.882699	0.10	1552.50
788	\N	52	2024-09-27	9590.00	1	2025-08-03 19:57:55.161493	2025-08-03 19:57:55.161493	0.50	4795.00
789	\N	57	2024-09-27	1155.00	1	2025-08-03 19:57:55.390698	2025-08-03 19:57:55.390698	0.51	585.00
790	\N	57	2024-09-27	1015.00	1	2025-08-03 19:57:55.649462	2025-08-03 19:57:55.649462	0.79	805.00
791	\N	43	2024-09-30	12625.00	1	2025-08-03 19:57:55.877972	2025-08-03 19:57:55.877972	0.50	6312.50
792	\N	44	2024-09-30	8755.00	1	2025-08-03 19:57:56.147527	2025-08-03 19:57:56.147527	0.63	5537.36
793	\N	44	2024-09-30	8425.00	1	2025-08-03 19:57:56.407534	2025-08-03 19:57:56.407534	0.42	3575.34
794	\N	44	2024-09-30	8735.00	1	2025-08-03 19:57:56.732569	2025-08-03 19:57:56.732569	0.32	2788.70
795	\N	44	2024-09-30	6415.00	1	2025-08-03 19:57:57.048447	2025-08-03 19:57:57.048447	0.70	4490.50
796	\N	44	2024-09-30	6320.00	1	2025-08-03 19:57:57.309353	2025-08-03 19:57:57.309353	0.50	3145.10
797	\N	45	2024-09-30	8710.79	1	2025-08-03 19:57:57.569968	2025-08-03 19:57:57.569968	0.50	4355.35
798	\N	94	2024-09-30	10870.00	1	2025-08-03 19:57:57.937483	2025-08-03 19:57:57.937483	0.66	7138.86
799	\N	52	2024-09-30	2875.00	1	2025-08-03 19:57:58.209268	2025-08-03 19:57:58.209268	0.50	1437.50
800	\N	53	2024-09-30	7020.57	1	2025-08-03 19:57:58.469288	2025-08-03 19:57:58.469288	0.71	5000.00
801	\N	44	2024-10-01	4565.00	1	2025-08-03 19:57:58.733732	2025-08-03 19:57:58.733732	0.70	3195.00
802	\N	44	2024-10-01	8255.00	1	2025-08-03 19:57:59.00351	2025-08-03 19:57:59.00351	0.64	5309.53
803	\N	44	2024-10-01	6755.00	1	2025-08-03 19:57:59.219241	2025-08-03 19:57:59.219241	0.25	1666.66
804	\N	85	2024-10-01	3350.00	1	2025-08-03 19:57:59.471114	2025-08-03 19:57:59.471114	0.60	2010.00
805	\N	127	2024-10-01	16605.00	1	2025-08-03 19:57:59.745001	2025-08-03 19:57:59.745001	0.50	8302.50
806	\N	60	2024-10-01	6945.00	1	2025-08-03 19:58:00.005695	2025-08-03 19:58:00.005695	0.55	3819.75
807	\N	129	2024-10-01	12376.00	1	2025-08-03 19:58:00.27771	2025-08-03 19:58:00.27771	0.65	8044.40
808	\N	45	2024-10-02	5930.00	1	2025-08-03 19:58:00.545206	2025-08-03 19:58:00.545206	0.42	2500.00
809	\N	137	2024-10-02	3795.00	1	2025-08-03 19:58:00.873408	2025-08-03 19:58:00.873408	0.42	1581.25
810	\N	156	2024-10-02	6000.00	1	2025-08-03 19:58:01.331118	2025-08-03 19:58:01.331118	0.37	2200.00
811	\N	80	2024-10-02	9020.00	1	2025-08-03 19:58:01.584437	2025-08-03 19:58:01.584437	0.27	2435.40
812	\N	80	2024-10-02	11150.00	1	2025-08-03 19:58:01.852448	2025-08-03 19:58:01.852448	0.29	3233.50
813	\N	55	2024-10-02	6895.00	1	2025-08-03 19:58:02.207185	2025-08-03 19:58:02.207185	0.47	3267.63
814	\N	52	2024-10-02	5603.27	1	2025-08-03 19:58:02.478367	2025-08-03 19:58:02.478367	0.50	2803.00
815	\N	52	2024-10-02	5518.75	1	2025-08-03 19:58:02.74266	2025-08-03 19:58:02.74266	0.50	2760.00
816	\N	53	2024-10-02	5085.00	1	2025-08-03 19:58:03.009863	2025-08-03 19:58:03.009863	0.59	3000.00
817	\N	44	2024-10-03	7682.90	1	2025-08-03 19:58:03.275907	2025-08-03 19:58:03.275907	0.27	2053.62
818	\N	44	2024-10-03	6380.00	1	2025-08-03 19:58:03.538063	2025-08-03 19:58:03.538063	0.70	4466.00
819	\N	44	2024-10-03	2202.72	1	2025-08-03 19:58:03.809639	2025-08-03 19:58:03.809639	0.70	1541.91
820	\N	44	2024-10-03	3590.00	1	2025-08-03 19:58:04.056777	2025-08-03 19:58:04.056777	0.70	2513.00
821	\N	44	2024-10-03	1410.00	1	2025-08-03 19:58:04.315278	2025-08-03 19:58:04.315278	0.59	833.33
822	\N	44	2024-10-03	7675.00	1	2025-08-03 19:58:04.577961	2025-08-03 19:58:04.577961	0.70	5372.50
823	\N	55	2024-10-03	8770.00	1	2025-08-03 19:58:04.935304	2025-08-03 19:58:04.935304	0.35	3069.50
824	\N	55	2024-10-03	6650.00	1	2025-08-03 19:58:05.197878	2025-08-03 19:58:05.197878	0.49	3276.81
825	\N	52	2024-10-03	5522.15	1	2025-08-03 19:58:05.466777	2025-08-03 19:58:05.466777	0.50	2762.00
826	\N	57	2024-10-03	6520.00	1	2025-08-03 19:58:05.754598	2025-08-03 19:58:05.754598	0.63	4095.00
827	\N	45	2024-10-04	2575.00	1	2025-08-03 19:58:06.012594	2025-08-03 19:58:06.012594	0.50	1287.50
828	\N	55	2024-10-04	3735.00	1	2025-08-03 19:58:06.279037	2025-08-03 19:58:06.279037	0.43	1607.97
829	\N	110	2024-10-04	3865.00	1	2025-08-03 19:58:06.538845	2025-08-03 19:58:06.538845	0.65	2512.25
830	\N	116	2024-10-04	8505.00	1	2025-08-03 19:58:06.755572	2025-08-03 19:58:06.755572	0.50	4252.50
831	\N	43	2024-10-07	6425.00	1	2025-08-03 19:58:07.02007	2025-08-03 19:58:07.02007	0.50	3212.50
832	\N	43	2024-10-07	6235.00	1	2025-08-03 19:58:07.22619	2025-08-03 19:58:07.22619	0.50	3117.50
833	\N	43	2024-10-07	4085.00	1	2025-08-03 19:58:07.491049	2025-08-03 19:58:07.491049	0.50	2042.50
834	\N	43	2024-10-07	5990.00	1	2025-08-03 19:58:07.752294	2025-08-03 19:58:07.752294	0.50	2995.00
835	\N	43	2024-10-07	3405.00	1	2025-08-03 19:58:08.011914	2025-08-03 19:58:08.011914	0.66	2250.00
836	\N	43	2024-10-07	4534.15	1	2025-08-03 19:58:08.283645	2025-08-03 19:58:08.283645	0.65	2948.00
837	\N	43	2024-10-07	6150.00	1	2025-08-03 19:58:08.560794	2025-08-03 19:58:08.560794	0.50	3075.00
838	\N	43	2024-10-07	5720.00	1	2025-08-03 19:58:08.824563	2025-08-03 19:58:08.824563	0.60	3432.00
839	\N	44	2024-10-07	1350.00	1	2025-08-03 19:58:09.092266	2025-08-03 19:58:09.092266	0.70	945.00
840	\N	44	2024-10-07	6470.00	1	2025-08-03 19:58:09.360794	2025-08-03 19:58:09.360794	0.70	4529.00
841	\N	44	2024-10-07	6850.00	1	2025-08-03 19:58:09.629656	2025-08-03 19:58:09.629656	0.50	3425.00
842	\N	44	2024-10-07	6180.00	1	2025-08-03 19:58:09.892736	2025-08-03 19:58:09.892736	0.50	3090.00
843	\N	88	2024-10-07	4320.00	1	2025-08-03 19:58:10.161334	2025-08-03 19:58:10.161334	0.34	1468.80
844	\N	88	2024-10-07	6630.00	1	2025-08-03 19:58:10.375584	2025-08-03 19:58:10.375584	0.66	4392.26
845	\N	80	2024-10-07	5530.00	1	2025-08-03 19:58:10.748582	2025-08-03 19:58:10.748582	0.60	3318.00
846	\N	133	2024-10-07	8380.00	1	2025-08-03 19:58:11.013547	2025-08-03 19:58:11.013547	0.50	4190.00
847	\N	55	2024-10-07	2678.29	1	2025-08-03 19:58:11.278562	2025-08-03 19:58:11.278562	0.68	1816.82
848	\N	55	2024-10-07	5665.00	1	2025-08-03 19:58:11.526985	2025-08-03 19:58:11.526985	0.35	1965.25
849	\N	55	2024-10-07	2880.00	1	2025-08-03 19:58:11.801151	2025-08-03 19:58:11.801151	0.41	1169.68
850	\N	52	2024-10-07	7895.00	1	2025-08-03 19:58:12.072247	2025-08-03 19:58:12.072247	0.50	3947.50
851	\N	52	2024-10-07	7230.00	1	2025-08-03 19:58:12.339622	2025-08-03 19:58:12.339622	0.50	3615.00
852	\N	57	2024-10-07	2045.00	1	2025-08-03 19:58:12.68627	2025-08-03 19:58:12.68627	0.58	1195.00
853	\N	57	2024-10-07	6015.00	1	2025-08-03 19:58:13.042969	2025-08-03 19:58:13.042969	0.58	3465.00
854	\N	44	2024-10-08	11570.28	1	2025-08-03 19:58:13.322669	2025-08-03 19:58:13.322669	0.60	6912.00
855	\N	44	2024-10-08	7275.00	1	2025-08-03 19:58:13.545558	2025-08-03 19:58:13.545558	0.70	5092.00
856	\N	44	2024-10-08	7941.52	1	2025-08-03 19:58:13.833967	2025-08-03 19:58:13.833967	0.40	3205.74
857	\N	44	2024-10-08	8385.00	1	2025-08-03 19:58:14.102005	2025-08-03 19:58:14.102005	0.70	5869.50
858	\N	44	2024-10-08	9652.24	1	2025-08-03 19:58:14.508893	2025-08-03 19:58:14.508893	0.23	2250.38
859	\N	44	2024-10-08	6685.00	1	2025-08-03 19:58:14.777838	2025-08-03 19:58:14.777838	0.61	4052.05
860	\N	44	2024-10-08	5770.00	1	2025-08-03 19:58:15.054348	2025-08-03 19:58:15.054348	0.34	1980.00
861	\N	44	2024-10-08	5990.00	1	2025-08-03 19:58:15.336045	2025-08-03 19:58:15.336045	0.40	2409.16
862	\N	44	2024-10-08	6415.00	1	2025-08-03 19:58:15.597803	2025-08-03 19:58:15.597803	0.42	2666.67
863	\N	44	2024-10-08	9679.96	1	2025-08-03 19:58:15.8154	2025-08-03 19:58:15.8154	0.73	7088.00
864	\N	45	2024-10-08	6640.00	1	2025-08-03 19:58:16.08095	2025-08-03 19:58:16.08095	0.47	3133.72
865	\N	45	2024-10-08	8003.94	1	2025-08-03 19:58:16.310533	2025-08-03 19:58:16.310533	0.50	4001.97
866	\N	88	2024-10-08	5225.00	1	2025-08-03 19:58:16.582289	2025-08-03 19:58:16.582289	0.51	2666.67
867	\N	88	2024-10-08	14930.00	1	2025-08-03 19:58:16.854433	2025-08-03 19:58:16.854433	0.61	9107.30
868	\N	157	2024-10-08	2460.00	1	2025-08-03 19:58:17.329826	2025-08-03 19:58:17.329826	0.63	1560.00
869	\N	66	2024-10-08	11543.12	1	2025-08-03 19:58:17.566766	2025-08-03 19:58:17.566766	0.66	7675.67
870	\N	116	2024-10-08	4885.00	1	2025-08-03 19:58:17.842446	2025-08-03 19:58:17.842446	0.65	3175.25
871	\N	44	2024-10-09	4440.00	1	2025-08-03 19:58:18.140057	2025-08-03 19:58:18.140057	0.77	3404.33
872	\N	44	2024-10-09	6230.47	1	2025-08-03 19:58:18.364626	2025-08-03 19:58:18.364626	0.34	2127.00
873	\N	44	2024-10-09	8439.71	1	2025-08-03 19:58:18.63534	2025-08-03 19:58:18.63534	0.28	2321.00
874	\N	45	2024-10-09	3295.00	1	2025-08-03 19:58:18.890415	2025-08-03 19:58:18.890415	0.50	1647.50
875	\N	48	2024-10-09	5310.00	1	2025-08-03 19:58:19.164916	2025-08-03 19:58:19.164916	0.64	3400.00
876	\N	102	2024-10-09	6915.00	1	2025-08-03 19:58:19.425652	2025-08-03 19:58:19.425652	0.50	3457.50
877	\N	102	2024-10-09	6310.00	1	2025-08-03 19:58:19.698609	2025-08-03 19:58:19.698609	0.60	3786.00
878	\N	116	2024-10-09	4230.00	1	2025-08-03 19:58:19.970874	2025-08-03 19:58:19.970874	0.40	1692.00
879	\N	44	2024-10-10	9535.00	1	2025-08-03 19:58:20.243768	2025-08-03 19:58:20.243768	0.32	3083.35
880	\N	44	2024-10-10	7250.00	1	2025-08-03 19:58:20.497942	2025-08-03 19:58:20.497942	0.26	1907.88
881	\N	44	2024-10-10	5585.00	1	2025-08-03 19:58:20.768119	2025-08-03 19:58:20.768119	0.70	3909.50
882	\N	80	2024-10-10	1465.00	1	2025-08-03 19:58:21.135998	2025-08-03 19:58:21.135998	0.25	366.25
883	\N	58	2024-10-10	4450.00	1	2025-08-03 19:58:21.535469	2025-08-03 19:58:21.535469	0.56	2500.00
884	\N	55	2024-10-10	9860.73	1	2025-08-03 19:58:21.745873	2025-08-03 19:58:21.745873	0.34	3311.64
885	\N	53	2024-10-10	7395.00	1	2025-08-03 19:58:22.013864	2025-08-03 19:58:22.013864	0.54	4000.00
886	\N	43	2024-10-11	10115.00	1	2025-08-03 19:58:22.287307	2025-08-03 19:58:22.287307	0.60	6069.00
887	\N	43	2024-10-11	9855.00	1	2025-08-03 19:58:22.551773	2025-08-03 19:58:22.551773	0.60	5915.00
888	\N	44	2024-10-11	6975.00	1	2025-08-03 19:58:22.884475	2025-08-03 19:58:22.884475	0.70	4882.50
889	\N	44	2024-10-11	5320.00	1	2025-08-03 19:58:23.1122	2025-08-03 19:58:23.1122	0.33	1775.00
890	\N	44	2024-10-11	5198.54	1	2025-08-03 19:58:23.402992	2025-08-03 19:58:23.402992	0.40	2091.69
891	\N	45	2024-10-11	11947.35	1	2025-08-03 19:58:23.672168	2025-08-03 19:58:23.672168	0.50	5973.68
892	\N	66	2024-10-11	11601.42	1	2025-08-03 19:58:23.933954	2025-08-03 19:58:23.933954	0.65	7500.00
893	\N	53	2024-10-11	4980.00	1	2025-08-03 19:58:24.209938	2025-08-03 19:58:24.209938	1.00	4980.00
894	\N	53	2024-10-11	5468.31	1	2025-08-03 19:58:24.437385	2025-08-03 19:58:24.437385	0.55	3000.00
895	\N	44	2024-10-14	5980.00	1	2025-08-03 19:58:24.694701	2025-08-03 19:58:24.694701	0.31	1830.66
896	\N	44	2024-10-14	5650.47	1	2025-08-03 19:58:24.948497	2025-08-03 19:58:24.948497	0.34	1938.33
897	\N	44	2024-10-14	5515.20	1	2025-08-03 19:58:25.218865	2025-08-03 19:58:25.218865	0.72	3971.00
898	\N	44	2024-10-14	5895.00	1	2025-08-03 19:58:25.501523	2025-08-03 19:58:25.501523	0.38	2227.98
899	\N	44	2024-10-14	6010.00	1	2025-08-03 19:58:25.760041	2025-08-03 19:58:25.760041	0.14	833.33
900	\N	44	2024-10-14	7460.00	1	2025-08-03 19:58:26.027548	2025-08-03 19:58:26.027548	0.70	5222.00
901	\N	44	2024-10-14	7310.00	1	2025-08-03 19:58:26.392185	2025-08-03 19:58:26.392185	0.70	5117.00
902	\N	44	2024-10-14	4365.00	1	2025-08-03 19:58:26.674862	2025-08-03 19:58:26.674862	0.41	1799.66
903	\N	44	2024-10-14	1745.00	1	2025-08-03 19:58:26.960195	2025-08-03 19:58:26.960195	0.48	833.00
904	\N	55	2024-10-14	3260.00	1	2025-08-03 19:58:27.174737	2025-08-03 19:58:27.174737	0.37	1213.11
905	\N	158	2024-10-14	9885.00	1	2025-08-03 19:58:27.542642	2025-08-03 19:58:27.542642	0.65	6425.25
906	\N	116	2024-10-14	3665.00	1	2025-08-03 19:58:27.822479	2025-08-03 19:58:27.822479	0.75	2748.75
907	\N	53	2024-10-14	3964.67	1	2025-08-03 19:58:28.087992	2025-08-03 19:58:28.087992	0.68	2700.00
908	\N	44	2024-10-15	6970.00	1	2025-08-03 19:58:28.449169	2025-08-03 19:58:28.449169	0.62	4295.33
909	\N	44	2024-10-15	6340.00	1	2025-08-03 19:58:28.722025	2025-08-03 19:58:28.722025	0.36	2271.00
910	\N	44	2024-10-15	8580.65	1	2025-08-03 19:58:28.990865	2025-08-03 19:58:28.990865	0.42	3640.33
911	\N	44	2024-10-15	2440.00	1	2025-08-03 19:58:29.256505	2025-08-03 19:58:29.256505	0.70	1708.00
912	\N	44	2024-10-15	3180.00	1	2025-08-03 19:58:29.522339	2025-08-03 19:58:29.522339	0.61	1932.96
913	\N	103	2024-10-15	10411.68	1	2025-08-03 19:58:29.794711	2025-08-03 19:58:29.794711	0.60	6250.00
914	\N	65	2024-10-15	6095.00	1	2025-08-03 19:58:30.057023	2025-08-03 19:58:30.057023	0.60	3657.00
915	\N	154	2024-10-15	8070.00	1	2025-08-03 19:58:30.275328	2025-08-03 19:58:30.275328	0.74	6000.00
916	\N	55	2024-10-15	8280.00	1	2025-08-03 19:58:30.545992	2025-08-03 19:58:30.545992	0.36	2995.23
917	\N	116	2024-10-15	4440.00	1	2025-08-03 19:58:30.774375	2025-08-03 19:58:30.774375	0.61	2691.00
918	\N	116	2024-10-15	4790.00	1	2025-08-03 19:58:31.034024	2025-08-03 19:58:31.034024	0.60	2874.00
919	\N	57	2024-10-15	3145.00	1	2025-08-03 19:58:31.259979	2025-08-03 19:58:31.259979	0.58	1820.00
920	\N	60	2024-10-15	4485.00	1	2025-08-03 19:58:31.485157	2025-08-03 19:58:31.485157	0.67	3004.95
921	\N	53	2024-10-15	3755.00	1	2025-08-03 19:58:31.762813	2025-08-03 19:58:31.762813	0.80	3000.00
922	\N	43	2024-10-16	9285.00	1	2025-08-03 19:58:31.991743	2025-08-03 19:58:31.991743	0.50	4642.50
923	\N	44	2024-10-16	6750.00	1	2025-08-03 19:58:32.252593	2025-08-03 19:58:32.252593	0.70	4725.00
924	\N	44	2024-10-16	6645.00	1	2025-08-03 19:58:32.515411	2025-08-03 19:58:32.515411	0.70	4651.50
925	\N	44	2024-10-16	7235.00	1	2025-08-03 19:58:32.786017	2025-08-03 19:58:32.786017	0.23	1651.15
926	\N	44	2024-10-16	4470.00	1	2025-08-03 19:58:33.063438	2025-08-03 19:58:33.063438	0.70	3129.00
927	\N	44	2024-10-16	6435.00	1	2025-08-03 19:58:33.331169	2025-08-03 19:58:33.331169	0.45	2907.66
928	\N	159	2024-10-16	8820.00	1	2025-08-03 19:58:33.76564	2025-08-03 19:58:33.76564	0.37	3239.95
929	\N	55	2024-10-16	5502.31	1	2025-08-03 19:58:33.984498	2025-08-03 19:58:33.984498	0.47	2611.00
930	\N	57	2024-10-16	540.00	1	2025-08-03 19:58:34.253132	2025-08-03 19:58:34.253132	0.57	310.00
931	\N	85	2024-10-17	4285.00	1	2025-08-03 19:58:34.536557	2025-08-03 19:58:34.536557	0.55	2356.75
932	\N	48	2024-10-17	4305.00	1	2025-08-03 19:58:34.831486	2025-08-03 19:58:34.831486	0.53	2300.00
933	\N	55	2024-10-17	9350.00	1	2025-08-03 19:58:35.094873	2025-08-03 19:58:35.094873	0.50	4675.00
934	\N	102	2024-10-17	2715.00	1	2025-08-03 19:58:35.319859	2025-08-03 19:58:35.319859	0.70	1900.00
935	\N	102	2024-10-17	7530.00	1	2025-08-03 19:58:35.580695	2025-08-03 19:58:35.580695	0.60	4518.00
936	\N	116	2024-10-17	6790.00	1	2025-08-03 19:58:35.847233	2025-08-03 19:58:35.847233	0.84	5729.00
937	\N	116	2024-10-17	4160.00	1	2025-08-03 19:58:36.219564	2025-08-03 19:58:36.219564	0.56	2329.60
938	\N	57	2024-10-17	7105.00	1	2025-08-03 19:58:36.440096	2025-08-03 19:58:36.440096	0.43	3055.00
939	\N	53	2024-10-17	4898.94	1	2025-08-03 19:58:36.660823	2025-08-03 19:58:36.660823	0.61	3000.00
940	\N	44	2024-10-18	5065.00	1	2025-08-03 19:58:36.929042	2025-08-03 19:58:36.929042	0.43	2190.41
941	\N	44	2024-10-18	7125.00	1	2025-08-03 19:58:37.20424	2025-08-03 19:58:37.20424	0.59	4222.99
942	\N	44	2024-10-18	8900.00	1	2025-08-03 19:58:37.479705	2025-08-03 19:58:37.479705	0.37	3269.33
943	\N	44	2024-10-18	9423.00	1	2025-08-03 19:58:37.871737	2025-08-03 19:58:37.871737	0.70	6573.00
944	\N	44	2024-10-18	8123.54	1	2025-08-03 19:58:38.107909	2025-08-03 19:58:38.107909	0.63	5088.33
945	\N	160	2024-10-18	2410.00	1	2025-08-03 19:58:38.691316	2025-08-03 19:58:38.691316	0.40	964.00
946	\N	161	2024-10-18	12310.00	1	2025-08-03 19:58:39.137585	2025-08-03 19:58:39.137585	0.32	4000.00
947	\N	162	2024-10-18	12485.00	1	2025-08-03 19:58:39.62354	2025-08-03 19:58:39.62354	0.50	6242.50
948	\N	117	2024-10-18	7405.30	1	2025-08-03 19:58:39.860181	2025-08-03 19:58:39.860181	0.50	3702.65
949	\N	117	2024-10-18	1655.00	1	2025-08-03 19:58:40.074257	2025-08-03 19:58:40.074257	0.60	1000.00
950	\N	55	2024-10-18	9385.00	1	2025-08-03 19:58:40.409739	2025-08-03 19:58:40.409739	0.50	4692.50
951	\N	158	2024-10-18	14485.00	1	2025-08-03 19:58:40.710787	2025-08-03 19:58:40.710787	0.49	7097.65
952	\N	44	2024-10-21	8185.00	1	2025-08-03 19:58:41.018228	2025-08-03 19:58:41.018228	0.70	5729.50
953	\N	44	2024-10-21	2785.00	1	2025-08-03 19:58:41.254091	2025-08-03 19:58:41.254091	0.70	1949.50
954	\N	44	2024-10-21	6100.37	1	2025-08-03 19:58:41.4867	2025-08-03 19:58:41.4867	0.70	4270.26
955	\N	80	2024-10-21	1480.00	1	2025-08-03 19:58:41.752648	2025-08-03 19:58:41.752648	0.65	962.00
956	\N	102	2024-10-21	7383.19	1	2025-08-03 19:58:42.143446	2025-08-03 19:58:42.143446	0.60	4429.97
957	\N	102	2024-10-21	995.00	1	2025-08-03 19:58:42.374963	2025-08-03 19:58:42.374963	0.75	746.25
958	\N	44	2024-10-22	1675.00	1	2025-08-03 19:58:42.664432	2025-08-03 19:58:42.664432	0.70	1172.50
959	\N	44	2024-10-22	2535.00	1	2025-08-03 19:58:42.926499	2025-08-03 19:58:42.926499	0.66	1666.66
960	\N	44	2024-10-22	6220.00	1	2025-08-03 19:58:43.154881	2025-08-03 19:58:43.154881	0.63	3920.00
961	\N	45	2024-10-22	15735.00	1	2025-08-03 19:58:43.53558	2025-08-03 19:58:43.53558	0.40	6294.00
962	\N	45	2024-10-22	6420.65	1	2025-08-03 19:58:43.77147	2025-08-03 19:58:43.77147	0.50	3210.33
963	\N	163	2024-10-22	7145.26	1	2025-08-03 19:58:44.259746	2025-08-03 19:58:44.259746	0.70	5000.00
964	\N	55	2024-10-22	3710.00	1	2025-08-03 19:58:44.545794	2025-08-03 19:58:44.545794	0.43	1579.60
965	\N	52	2024-10-22	9585.00	1	2025-08-03 19:58:44.846253	2025-08-03 19:58:44.846253	0.40	3834.00
966	\N	52	2024-10-22	3251.25	1	2025-08-03 19:58:45.145634	2025-08-03 19:58:45.145634	0.62	2000.00
967	\N	60	2024-10-22	1950.00	1	2025-08-03 19:58:45.430732	2025-08-03 19:58:45.430732	0.70	1365.00
968	\N	44	2024-10-23	5390.00	1	2025-08-03 19:58:45.710093	2025-08-03 19:58:45.710093	0.70	3773.00
969	\N	44	2024-10-23	1808.75	1	2025-08-03 19:58:45.975233	2025-08-03 19:58:45.975233	0.70	1266.75
970	\N	44	2024-10-23	1885.00	1	2025-08-03 19:58:46.22593	2025-08-03 19:58:46.22593	0.70	1319.50
971	\N	117	2024-10-23	1120.00	1	2025-08-03 19:58:46.628744	2025-08-03 19:58:46.628744	0.50	560.00
972	\N	164	2024-10-23	5315.00	1	2025-08-03 19:58:47.191005	2025-08-03 19:58:47.191005	0.50	2657.50
973	\N	102	2024-10-23	15120.00	1	2025-08-03 19:58:47.458989	2025-08-03 19:58:47.458989	0.50	7515.00
974	\N	102	2024-10-23	2880.00	1	2025-08-03 19:58:47.788562	2025-08-03 19:58:47.788562	0.70	2016.00
975	\N	102	2024-10-23	9101.79	1	2025-08-03 19:58:48.085286	2025-08-03 19:58:48.085286	0.44	4014.66
976	\N	126	2024-10-23	7305.00	1	2025-08-03 19:58:48.412123	2025-08-03 19:58:48.412123	0.50	3650.00
977	\N	44	2024-10-24	11462.18	1	2025-08-03 19:58:48.694202	2025-08-03 19:58:48.694202	0.25	2865.55
978	\N	44	2024-10-24	8867.55	1	2025-08-03 19:58:48.941013	2025-08-03 19:58:48.941013	0.44	3869.66
979	\N	88	2024-10-24	14610.00	1	2025-08-03 19:58:49.3452	2025-08-03 19:58:49.3452	0.50	7305.00
980	\N	152	2024-10-24	6110.00	1	2025-08-03 19:58:49.638709	2025-08-03 19:58:49.638709	0.26	1574.20
981	\N	57	2024-10-24	3700.00	1	2025-08-03 19:58:49.970314	2025-08-03 19:58:49.970314	0.50	1850.00
982	\N	57	2024-10-24	3600.00	1	2025-08-03 19:58:50.289355	2025-08-03 19:58:50.289355	0.53	1900.00
983	\N	43	2024-10-25	6877.67	1	2025-08-03 19:58:50.534334	2025-08-03 19:58:50.534334	0.64	4425.00
984	\N	43	2024-10-25	11790.00	1	2025-08-03 19:58:50.782852	2025-08-03 19:58:50.782852	0.50	5895.00
985	\N	43	2024-10-25	10630.00	1	2025-08-03 19:58:51.030299	2025-08-03 19:58:51.030299	0.50	5315.00
986	\N	43	2024-10-25	5545.00	1	2025-08-03 19:58:51.266298	2025-08-03 19:58:51.266298	0.50	2772.50
987	\N	43	2024-10-25	8075.47	1	2025-08-03 19:58:51.514813	2025-08-03 19:58:51.514813	0.64	5200.00
988	\N	43	2024-10-25	10305.00	1	2025-08-03 19:58:51.737153	2025-08-03 19:58:51.737153	0.50	5152.50
989	\N	43	2024-10-25	1675.00	1	2025-08-03 19:58:52.007437	2025-08-03 19:58:52.007437	0.77	1285.00
990	\N	43	2024-10-25	8580.00	1	2025-08-03 19:58:52.287046	2025-08-03 19:58:52.287046	0.50	4290.00
991	\N	44	2024-10-25	9598.27	1	2025-08-03 19:58:52.555371	2025-08-03 19:58:52.555371	0.42	4051.90
992	\N	44	2024-10-25	11620.00	1	2025-08-03 19:58:52.785486	2025-08-03 19:58:52.785486	0.70	8134.00
993	\N	44	2024-10-25	4895.00	1	2025-08-03 19:58:53.017828	2025-08-03 19:58:53.017828	0.70	3426.50
994	\N	52	2024-10-25	4065.48	1	2025-08-03 19:58:53.278771	2025-08-03 19:58:53.278771	0.50	2034.00
995	\N	116	2024-10-25	6685.00	1	2025-08-03 19:58:53.535161	2025-08-03 19:58:53.535161	0.60	4011.00
996	\N	60	2024-10-25	4930.00	1	2025-08-03 19:58:53.795133	2025-08-03 19:58:53.795133	0.68	3351.00
997	\N	44	2024-10-28	8517.44	1	2025-08-03 19:58:54.088962	2025-08-03 19:58:54.088962	0.70	5962.21
998	\N	44	2024-10-28	5447.60	1	2025-08-03 19:58:54.378234	2025-08-03 19:58:54.378234	0.49	2649.66
999	\N	44	2024-10-28	7046.21	1	2025-08-03 19:58:54.641464	2025-08-03 19:58:54.641464	0.39	2744.54
1000	\N	44	2024-10-28	7056.25	1	2025-08-03 19:58:54.929718	2025-08-03 19:58:54.929718	0.35	2483.00
1001	\N	44	2024-10-28	2310.00	1	2025-08-03 19:58:55.151853	2025-08-03 19:58:55.151853	0.58	1333.33
1002	\N	44	2024-10-28	3545.00	1	2025-08-03 19:58:55.424751	2025-08-03 19:58:55.424751	0.70	2481.50
1003	\N	44	2024-10-28	3960.00	1	2025-08-03 19:58:55.698157	2025-08-03 19:58:55.698157	0.60	2376.00
1004	\N	44	2024-10-28	7874.40	1	2025-08-03 19:58:56.002809	2025-08-03 19:58:56.002809	0.66	5179.71
1005	\N	71	2024-10-28	12440.00	1	2025-08-03 19:58:56.218767	2025-08-03 19:58:56.218767	0.35	4354.00
1006	\N	102	2024-10-28	720.00	1	2025-08-03 19:58:56.493257	2025-08-03 19:58:56.493257	0.75	540.00
1007	\N	52	2024-10-28	10100.00	1	2025-08-03 19:58:56.758483	2025-08-03 19:58:56.758483	0.50	5050.00
1008	\N	126	2024-10-28	8525.00	1	2025-08-03 19:58:57.024523	2025-08-03 19:58:57.024523	0.50	4250.00
1009	\N	44	2024-10-29	7629.63	1	2025-08-03 19:58:57.295123	2025-08-03 19:58:57.295123	0.50	3825.64
1010	\N	44	2024-10-29	10800.52	1	2025-08-03 19:58:57.555865	2025-08-03 19:58:57.555865	0.59	6337.52
1011	\N	44	2024-10-29	9480.00	1	2025-08-03 19:58:57.766498	2025-08-03 19:58:57.766498	0.57	5384.42
1012	\N	131	2024-10-29	4230.00	1	2025-08-03 19:58:58.102089	2025-08-03 19:58:58.102089	0.66	2797.81
1013	\N	102	2024-10-29	2945.00	1	2025-08-03 19:58:58.389838	2025-08-03 19:58:58.389838	0.75	2208.75
1014	\N	88	2024-10-31	15770.00	1	2025-08-03 19:58:58.644773	2025-08-03 19:58:58.644773	0.42	6554.14
1015	\N	94	2024-10-31	9415.00	1	2025-08-03 19:58:59.011747	2025-08-03 19:58:59.011747	0.65	6119.75
1016	\N	94	2024-10-31	6510.00	1	2025-08-03 19:58:59.283255	2025-08-03 19:58:59.283255	0.65	4231.50
1017	\N	123	2024-10-31	3155.00	1	2025-08-03 19:58:59.545891	2025-08-03 19:58:59.545891	0.67	2100.00
1018	\N	44	2024-11-01	7125.00	1	2025-08-03 19:58:59.808227	2025-08-03 19:58:59.808227	0.45	3225.33
1019	\N	44	2024-11-01	4950.00	1	2025-08-03 19:59:00.07807	2025-08-03 19:59:00.07807	0.70	3465.00
1020	\N	48	2024-11-01	7422.65	1	2025-08-03 19:59:00.30077	2025-08-03 19:59:00.30077	0.65	4800.00
1021	\N	60	2024-11-01	5160.00	1	2025-08-03 19:59:00.572648	2025-08-03 19:59:00.572648	0.60	3096.00
1022	\N	44	2024-11-04	5815.00	1	2025-08-03 19:59:00.868925	2025-08-03 19:59:00.868925	0.70	4065.00
1023	\N	44	2024-11-04	5985.00	1	2025-08-03 19:59:01.162379	2025-08-03 19:59:01.162379	0.70	4189.50
1024	\N	44	2024-11-04	4155.00	1	2025-08-03 19:59:01.429921	2025-08-03 19:59:01.429921	0.70	2908.50
1025	\N	44	2024-11-04	7325.00	1	2025-08-03 19:59:01.703273	2025-08-03 19:59:01.703273	0.66	4868.50
1026	\N	44	2024-11-04	4640.00	1	2025-08-03 19:59:01.970361	2025-08-03 19:59:01.970361	0.37	1725.63
1027	\N	44	2024-11-04	11825.00	1	2025-08-03 19:59:02.235784	2025-08-03 19:59:02.235784	0.70	8277.50
1028	\N	45	2024-11-04	5245.00	1	2025-08-03 19:59:02.455644	2025-08-03 19:59:02.455644	0.51	2667.50
1029	\N	165	2024-11-04	6330.00	1	2025-08-03 19:59:02.919581	2025-08-03 19:59:02.919581	0.50	3165.00
1030	\N	64	2024-11-04	1475.00	1	2025-08-03 19:59:03.170278	2025-08-03 19:59:03.170278	0.59	868.77
1031	\N	66	2024-11-04	3960.00	1	2025-08-03 19:59:03.465578	2025-08-03 19:59:03.465578	0.55	2178.00
1032	\N	132	2024-11-04	15840.00	1	2025-08-03 19:59:03.683985	2025-08-03 19:59:03.683985	0.50	7920.00
1033	\N	102	2024-11-04	4758.00	1	2025-08-03 19:59:03.913664	2025-08-03 19:59:03.913664	0.70	3330.60
1034	\N	52	2024-11-04	11381.20	1	2025-08-03 19:59:04.172339	2025-08-03 19:59:04.172339	0.50	5692.00
1035	\N	52	2024-11-04	7285.00	1	2025-08-03 19:59:04.441667	2025-08-03 19:59:04.441667	0.50	3642.50
1036	\N	44	2024-11-05	7100.00	1	2025-08-03 19:59:04.717701	2025-08-03 19:59:04.717701	0.68	4800.00
1037	\N	44	2024-11-05	8740.00	1	2025-08-03 19:59:04.989858	2025-08-03 19:59:04.989858	0.31	2712.99
1038	\N	44	2024-11-05	11190.00	1	2025-08-03 19:59:05.254941	2025-08-03 19:59:05.254941	0.70	7833.00
1039	\N	45	2024-11-05	7955.00	1	2025-08-03 19:59:05.534924	2025-08-03 19:59:05.534924	0.50	3977.50
1040	\N	45	2024-11-05	5600.00	1	2025-08-03 19:59:05.81799	2025-08-03 19:59:05.81799	0.50	2800.00
1041	\N	45	2024-11-05	6080.00	1	2025-08-03 19:59:06.188485	2025-08-03 19:59:06.188485	0.49	3000.00
1042	\N	166	2024-11-05	7340.00	1	2025-08-03 19:59:06.657327	2025-08-03 19:59:06.657327	0.66	4844.40
1043	\N	167	2024-11-05	9270.00	1	2025-08-03 19:59:07.118115	2025-08-03 19:59:07.118115	0.50	4635.00
1044	\N	132	2024-11-05	17880.00	1	2025-08-03 19:59:07.33476	2025-08-03 19:59:07.33476	0.50	8940.00
1045	\N	48	2024-11-05	7136.53	1	2025-08-03 19:59:07.599551	2025-08-03 19:59:07.599551	0.70	5000.00
1046	\N	131	2024-11-05	5550.00	1	2025-08-03 19:59:07.880426	2025-08-03 19:59:07.880426	0.70	3885.00
1047	\N	55	2024-11-05	5185.00	1	2025-08-03 19:59:08.123886	2025-08-03 19:59:08.123886	0.48	2488.41
1048	\N	55	2024-11-05	6510.00	1	2025-08-03 19:59:08.360263	2025-08-03 19:59:08.360263	0.58	3745.25
1049	\N	55	2024-11-05	8140.00	1	2025-08-03 19:59:08.542428	2025-08-03 19:59:08.542428	0.76	6150.28
1050	\N	55	2024-11-05	5200.00	1	2025-08-03 19:59:08.884272	2025-08-03 19:59:08.884272	0.65	3380.00
1051	\N	55	2024-11-05	7725.00	1	2025-08-03 19:59:09.112031	2025-08-03 19:59:09.112031	0.39	2986.28
1052	\N	55	2024-11-05	6965.00	1	2025-08-03 19:59:09.342778	2025-08-03 19:59:09.342778	0.33	2310.57
1053	\N	55	2024-11-05	7675.00	1	2025-08-03 19:59:09.575424	2025-08-03 19:59:09.575424	0.50	3827.86
1054	\N	102	2024-11-05	616.78	1	2025-08-03 19:59:09.821747	2025-08-03 19:59:09.821747	0.00	0.00
1055	\N	60	2024-11-05	5580.00	1	2025-08-03 19:59:10.163557	2025-08-03 19:59:10.163557	0.67	3738.60
1056	\N	44	2024-11-06	4140.00	1	2025-08-03 19:59:10.40309	2025-08-03 19:59:10.40309	0.70	2898.00
1057	\N	44	2024-11-06	6063.35	1	2025-08-03 19:59:10.640546	2025-08-03 19:59:10.640546	0.53	3187.60
1058	\N	127	2024-11-06	8915.00	1	2025-08-03 19:59:10.984139	2025-08-03 19:59:10.984139	0.55	4903.25
1059	\N	88	2024-11-06	11435.00	1	2025-08-03 19:59:11.230224	2025-08-03 19:59:11.230224	0.41	4700.00
1060	\N	94	2024-11-06	8945.00	1	2025-08-03 19:59:11.399414	2025-08-03 19:59:11.399414	0.60	5367.00
1061	\N	55	2024-11-06	10075.00	1	2025-08-03 19:59:11.625174	2025-08-03 19:59:11.625174	0.46	4629.88
1062	\N	55	2024-11-06	3635.00	1	2025-08-03 19:59:11.863492	2025-08-03 19:59:11.863492	0.55	2016.76
1063	\N	116	2024-11-06	9640.00	1	2025-08-03 19:59:12.088296	2025-08-03 19:59:12.088296	0.51	4916.40
1064	\N	60	2024-11-06	1105.00	1	2025-08-03 19:59:12.341508	2025-08-03 19:59:12.341508	0.60	663.00
1065	\N	44	2024-11-07	5744.85	1	2025-08-03 19:59:12.585729	2025-08-03 19:59:12.585729	0.43	2480.00
1066	\N	44	2024-11-07	5070.00	1	2025-08-03 19:59:12.844381	2025-08-03 19:59:12.844381	0.42	2154.33
1067	\N	44	2024-11-07	2160.00	1	2025-08-03 19:59:13.038505	2025-08-03 19:59:13.038505	0.51	1104.45
1068	\N	88	2024-11-07	15926.89	1	2025-08-03 19:59:13.283603	2025-08-03 19:59:13.283603	0.44	7000.00
1069	\N	93	2024-11-07	740.00	1	2025-08-03 19:59:13.458737	2025-08-03 19:59:13.458737	0.50	370.00
1070	\N	48	2024-11-07	5460.00	1	2025-08-03 19:59:13.720275	2025-08-03 19:59:13.720275	0.31	1700.00
1071	\N	48	2024-11-07	13392.08	1	2025-08-03 19:59:13.979333	2025-08-03 19:59:13.979333	0.40	5300.00
1072	\N	48	2024-11-07	6440.00	1	2025-08-03 19:59:14.233923	2025-08-03 19:59:14.233923	0.31	2000.00
1073	\N	52	2024-11-07	6891.46	1	2025-08-03 19:59:14.582676	2025-08-03 19:59:14.582676	0.50	3446.00
1074	\N	116	2024-11-07	9150.00	1	2025-08-03 19:59:14.767606	2025-08-03 19:59:14.767606	0.54	4941.00
1075	\N	57	2024-11-07	3050.00	1	2025-08-03 19:59:15.108699	2025-08-03 19:59:15.108699	0.61	1850.00
1076	\N	57	2024-11-07	2900.00	1	2025-08-03 19:59:15.482514	2025-08-03 19:59:15.482514	0.59	1700.00
1077	\N	57	2024-11-07	825.00	1	2025-08-03 19:59:15.728163	2025-08-03 19:59:15.728163	0.82	675.00
1078	\N	44	2024-11-08	645.00	1	2025-08-03 19:59:16.060965	2025-08-03 19:59:16.060965	0.70	451.50
1079	\N	44	2024-11-08	4175.00	1	2025-08-03 19:59:16.254827	2025-08-03 19:59:16.254827	0.52	2183.83
1080	\N	44	2024-11-08	4975.00	1	2025-08-03 19:59:16.48366	2025-08-03 19:59:16.48366	0.70	3482.50
1081	\N	44	2024-11-08	5465.00	1	2025-08-03 19:59:16.709159	2025-08-03 19:59:16.709159	0.70	3825.50
1082	\N	44	2024-11-08	9590.00	1	2025-08-03 19:59:16.939096	2025-08-03 19:59:16.939096	0.42	4008.32
1083	\N	102	2024-11-08	7590.00	1	2025-08-03 19:59:17.114631	2025-08-03 19:59:17.114631	0.50	3795.00
1084	\N	102	2024-11-08	5871.07	1	2025-08-03 19:59:17.357264	2025-08-03 19:59:17.357264	0.63	3727.50
1085	\N	44	2024-11-11	6990.00	1	2025-08-03 19:59:17.53181	2025-08-03 19:59:17.53181	0.69	4858.00
1086	\N	44	2024-11-11	6045.00	1	2025-08-03 19:59:17.878963	2025-08-03 19:59:17.878963	0.70	4231.50
1087	\N	71	2024-11-11	9670.00	1	2025-08-03 19:59:18.146783	2025-08-03 19:59:18.146783	0.35	3384.50
1088	\N	48	2024-11-11	10050.19	1	2025-08-03 19:59:18.412053	2025-08-03 19:59:18.412053	0.60	6030.11
1089	\N	84	2024-11-11	3681.22	1	2025-08-03 19:59:18.769016	2025-08-03 19:59:18.769016	0.75	2750.00
1090	\N	44	2024-11-12	10163.52	1	2025-08-03 19:59:19.154647	2025-08-03 19:59:19.154647	0.60	6098.32
1091	\N	44	2024-11-12	1965.00	1	2025-08-03 19:59:19.521805	2025-08-03 19:59:19.521805	0.76	1490.00
1092	\N	44	2024-11-12	4595.00	1	2025-08-03 19:59:19.712376	2025-08-03 19:59:19.712376	0.38	1735.78
1093	\N	88	2024-11-12	9665.00	1	2025-08-03 19:59:19.94414	2025-08-03 19:59:19.94414	0.45	4320.52
1094	\N	122	2024-11-12	8135.00	1	2025-08-03 19:59:20.171058	2025-08-03 19:59:20.171058	0.45	3660.00
1095	\N	55	2024-11-12	7920.00	1	2025-08-03 19:59:20.374128	2025-08-03 19:59:20.374128	0.70	5544.00
1096	\N	55	2024-11-12	11299.52	1	2025-08-03 19:59:20.600731	2025-08-03 19:59:20.600731	0.42	4700.00
1097	\N	55	2024-11-12	4720.00	1	2025-08-03 19:59:20.811312	2025-08-03 19:59:20.811312	0.46	2188.39
1098	\N	110	2024-11-12	17635.00	1	2025-08-03 19:59:21.023943	2025-08-03 19:59:21.023943	0.40	7054.00
1099	\N	116	2024-11-12	2785.00	1	2025-08-03 19:59:21.401875	2025-08-03 19:59:21.401875	0.75	2088.75
1100	\N	60	2024-11-12	9572.90	1	2025-08-03 19:59:21.607494	2025-08-03 19:59:21.607494	0.40	3829.16
1101	\N	57	2024-11-13	905.00	1	2025-08-03 19:59:22.017061	2025-08-03 19:59:22.017061	0.72	655.00
1102	\N	44	2024-11-13	7940.00	1	2025-08-03 19:59:22.269518	2025-08-03 19:59:22.269518	0.70	5558.00
1103	\N	44	2024-11-13	7040.50	1	2025-08-03 19:59:22.509401	2025-08-03 19:59:22.509401	0.50	3520.25
1104	\N	45	2024-11-13	6080.00	1	2025-08-03 19:59:22.87068	2025-08-03 19:59:22.87068	0.49	3000.00
1105	\N	88	2024-11-13	2515.00	1	2025-08-03 19:59:23.063034	2025-08-03 19:59:23.063034	0.50	1257.50
1106	\N	88	2024-11-13	11915.00	1	2025-08-03 19:59:23.283977	2025-08-03 19:59:23.283977	0.53	6350.00
1107	\N	90	2024-11-13	1315.00	1	2025-08-03 19:59:23.609545	2025-08-03 19:59:23.609545	0.51	664.08
1108	\N	55	2024-11-13	9225.00	1	2025-08-03 19:59:23.834369	2025-08-03 19:59:23.834369	0.50	4612.50
1109	\N	55	2024-11-13	7885.00	1	2025-08-03 19:59:24.065822	2025-08-03 19:59:24.065822	0.50	3942.50
1110	\N	55	2024-11-13	7645.00	1	2025-08-03 19:59:24.292702	2025-08-03 19:59:24.292702	0.50	3822.50
1111	\N	44	2024-11-14	7240.00	1	2025-08-03 19:59:24.522902	2025-08-03 19:59:24.522902	0.50	3590.00
1112	\N	44	2024-11-14	7685.57	1	2025-08-03 19:59:24.705399	2025-08-03 19:59:24.705399	0.60	4611.34
1113	\N	44	2024-11-14	5460.00	1	2025-08-03 19:59:25.044727	2025-08-03 19:59:25.044727	0.66	3610.00
1114	\N	44	2024-11-14	1240.00	1	2025-08-03 19:59:25.278522	2025-08-03 19:59:25.278522	0.70	868.00
1115	\N	44	2024-11-14	9438.32	1	2025-08-03 19:59:25.505486	2025-08-03 19:59:25.505486	0.70	6606.83
1116	\N	85	2024-11-14	1725.00	1	2025-08-03 19:59:25.796402	2025-08-03 19:59:25.796402	0.50	862.50
1117	\N	71	2024-11-14	995.00	1	2025-08-03 19:59:26.028756	2025-08-03 19:59:26.028756	0.43	427.66
1118	\N	152	2024-11-14	11975.00	1	2025-08-03 19:59:26.245165	2025-08-03 19:59:26.245165	0.50	5987.50
1119	\N	48	2024-11-14	6332.90	1	2025-08-03 19:59:26.479355	2025-08-03 19:59:26.479355	0.60	3800.00
1120	\N	52	2024-11-14	1395.00	1	2025-08-03 19:59:26.722461	2025-08-03 19:59:26.722461	0.50	697.50
1121	\N	116	2024-11-14	5390.00	1	2025-08-03 19:59:26.966832	2025-08-03 19:59:26.966832	0.65	3503.50
1122	\N	57	2024-11-14	500.00	1	2025-08-03 19:59:27.283831	2025-08-03 19:59:27.283831	0.50	250.00
1123	\N	53	2024-11-14	6675.00	1	2025-08-03 19:59:27.512676	2025-08-03 19:59:27.512676	0.70	4700.00
1124	\N	44	2024-11-15	3670.00	1	2025-08-03 19:59:27.733974	2025-08-03 19:59:27.733974	0.52	1893.48
1125	\N	45	2024-11-15	9148.10	1	2025-08-03 19:59:27.972275	2025-08-03 19:59:27.972275	0.50	4600.00
1126	\N	105	2024-11-15	2930.00	1	2025-08-03 19:59:28.183684	2025-08-03 19:59:28.183684	0.65	1900.00
1127	\N	168	2024-11-15	2015.00	1	2025-08-03 19:59:28.577663	2025-08-03 19:59:28.577663	0.53	1063.00
1128	\N	53	2024-11-15	4286.16	1	2025-08-03 19:59:28.777437	2025-08-03 19:59:28.777437	0.70	3000.00
1129	\N	80	2024-11-18	12555.00	1	2025-08-03 19:59:29.009437	2025-08-03 19:59:29.009437	0.55	6905.25
1130	\N	122	2024-11-18	10235.00	1	2025-08-03 19:59:29.229784	2025-08-03 19:59:29.229784	0.55	5600.00
1131	\N	122	2024-11-18	3125.00	1	2025-08-03 19:59:29.455007	2025-08-03 19:59:29.455007	0.50	1550.00
1132	\N	122	2024-11-18	3115.00	1	2025-08-03 19:59:29.75589	2025-08-03 19:59:29.75589	0.50	1550.00
1133	\N	48	2024-11-18	5527.20	1	2025-08-03 19:59:29.983803	2025-08-03 19:59:29.983803	0.60	3320.00
1134	\N	55	2024-11-18	5051.01	1	2025-08-03 19:59:30.174488	2025-08-03 19:59:30.174488	0.47	2356.73
1135	\N	84	2024-11-18	4715.00	1	2025-08-03 19:59:30.408001	2025-08-03 19:59:30.408001	0.74	3495.00
1136	\N	55	2024-11-19	5320.00	1	2025-08-03 19:59:30.639145	2025-08-03 19:59:30.639145	0.48	2540.00
1137	\N	94	2024-11-19	3807.65	1	2025-08-03 19:59:30.869908	2025-08-03 19:59:30.869908	0.68	2600.00
1138	\N	48	2024-11-19	3300.00	1	2025-08-03 19:59:31.199708	2025-08-03 19:59:31.199708	0.61	2000.00
1139	\N	43	2024-11-19	5305.00	1	2025-08-03 19:59:31.412654	2025-08-03 19:59:31.412654	0.50	2652.50
1140	\N	43	2024-11-19	3490.00	1	2025-08-03 19:59:31.628512	2025-08-03 19:59:31.628512	0.50	1745.00
1141	\N	44	2024-11-19	9304.82	1	2025-08-03 19:59:31.852524	2025-08-03 19:59:31.852524	0.35	3256.08
1142	\N	45	2024-11-19	3990.00	1	2025-08-03 19:59:32.075636	2025-08-03 19:59:32.075636	0.50	1995.00
1143	\N	88	2024-11-19	13922.88	1	2025-08-03 19:59:32.29065	2025-08-03 19:59:32.29065	0.55	7657.58
1144	\N	48	2024-11-19	4455.00	1	2025-08-03 19:59:32.526292	2025-08-03 19:59:32.526292	0.49	2200.00
1145	\N	48	2024-11-19	8191.00	1	2025-08-03 19:59:32.753873	2025-08-03 19:59:32.753873	0.55	4505.05
1146	\N	55	2024-11-19	6245.00	1	2025-08-03 19:59:32.974934	2025-08-03 19:59:32.974934	0.68	4275.65
1147	\N	55	2024-11-19	3777.40	1	2025-08-03 19:59:33.288896	2025-08-03 19:59:33.288896	0.35	1322.09
1148	\N	55	2024-11-19	3293.68	1	2025-08-03 19:59:33.513433	2025-08-03 19:59:33.513433	0.35	1152.79
1149	\N	84	2024-11-19	2080.00	1	2025-08-03 19:59:33.742946	2025-08-03 19:59:33.742946	0.14	300.00
1150	\N	55	2024-11-20	4493.39	1	2025-08-03 19:59:33.92421	2025-08-03 19:59:33.92421	0.35	1572.69
1151	\N	44	2024-11-20	11865.00	1	2025-08-03 19:59:34.167413	2025-08-03 19:59:34.167413	0.51	6069.66
1152	\N	44	2024-11-20	9804.47	1	2025-08-03 19:59:34.402018	2025-08-03 19:59:34.402018	0.41	4048.33
1153	\N	169	2024-11-20	5410.00	1	2025-08-03 19:59:34.898176	2025-08-03 19:59:34.898176	0.60	3246.00
1154	\N	45	2024-11-20	1145.00	1	2025-08-03 19:59:35.143045	2025-08-03 19:59:35.143045	0.50	572.50
1155	\N	55	2024-11-20	4742.38	1	2025-08-03 19:59:35.316189	2025-08-03 19:59:35.316189	0.35	1659.83
1156	\N	44	2024-11-21	4030.00	1	2025-08-03 19:59:35.541681	2025-08-03 19:59:35.541681	0.70	2821.00
1157	\N	170	2024-11-21	1755.00	1	2025-08-03 19:59:35.929337	2025-08-03 19:59:35.929337	0.57	1000.00
1158	\N	45	2024-11-21	10049.72	1	2025-08-03 19:59:36.098447	2025-08-03 19:59:36.098447	0.43	4300.00
1159	\N	121	2024-11-21	960.00	1	2025-08-03 19:59:36.31916	2025-08-03 19:59:36.31916	0.13	120.00
1160	\N	83	2024-11-21	4035.00	1	2025-08-03 19:59:36.564688	2025-08-03 19:59:36.564688	0.50	2017.50
1161	\N	66	2024-11-21	8565.00	1	2025-08-03 19:59:36.797345	2025-08-03 19:59:36.797345	0.60	5139.00
1162	\N	55	2024-11-21	3955.00	1	2025-08-03 19:59:37.025332	2025-08-03 19:59:37.025332	0.25	988.75
1163	\N	52	2024-11-21	7928.49	1	2025-08-03 19:59:37.247192	2025-08-03 19:59:37.247192	0.50	3964.00
1164	\N	52	2024-11-21	13046.89	1	2025-08-03 19:59:37.477604	2025-08-03 19:59:37.477604	0.50	6523.00
1165	\N	44	2024-11-22	6435.00	1	2025-08-03 19:59:37.737776	2025-08-03 19:59:37.737776	0.70	4504.50
1166	\N	44	2024-11-22	4295.00	1	2025-08-03 19:59:37.991774	2025-08-03 19:59:37.991774	0.70	3006.50
1167	\N	44	2024-11-22	2115.00	1	2025-08-03 19:59:38.24533	2025-08-03 19:59:38.24533	0.59	1255.00
1168	\N	171	2024-11-22	4265.17	1	2025-08-03 19:59:38.6464	2025-08-03 19:59:38.6464	0.94	4000.00
1169	\N	171	2024-11-22	3067.08	1	2025-08-03 19:59:38.900258	2025-08-03 19:59:38.900258	0.98	3000.00
1170	\N	86	2024-11-22	3690.00	1	2025-08-03 19:59:39.139982	2025-08-03 19:59:39.139982	0.75	2767.50
1171	\N	172	2024-11-22	8870.00	1	2025-08-03 19:59:39.517204	2025-08-03 19:59:39.517204	0.50	4435.00
1172	\N	110	2024-11-22	6160.00	1	2025-08-03 19:59:39.697099	2025-08-03 19:59:39.697099	0.50	3080.00
1173	\N	110	2024-11-22	8641.28	1	2025-08-03 19:59:39.879491	2025-08-03 19:59:39.879491	0.55	4752.66
1174	\N	116	2024-11-22	7820.00	1	2025-08-03 19:59:40.609723	2025-08-03 19:59:40.609723	0.51	4000.00
1175	\N	116	2024-11-22	4240.00	1	2025-08-03 19:59:40.915529	2025-08-03 19:59:40.915529	0.24	1000.00
1176	\N	57	2024-11-22	2610.00	1	2025-08-03 19:59:41.186933	2025-08-03 19:59:41.186933	0.52	1367.67
1177	\N	44	2024-11-25	6125.00	1	2025-08-03 19:59:41.399556	2025-08-03 19:59:41.399556	0.58	3533.66
1178	\N	44	2024-11-25	3300.00	1	2025-08-03 19:59:41.723718	2025-08-03 19:59:41.723718	0.58	1917.68
1179	\N	85	2024-11-25	3340.00	1	2025-08-03 19:59:41.921857	2025-08-03 19:59:41.921857	0.55	1837.00
1180	\N	88	2024-11-25	7230.00	1	2025-08-03 19:59:42.253738	2025-08-03 19:59:42.253738	0.51	3687.30
1181	\N	134	2024-11-25	9788.62	1	2025-08-03 19:59:42.512211	2025-08-03 19:59:42.512211	0.60	5873.17
1182	\N	66	2024-11-25	6975.00	1	2025-08-03 19:59:42.764227	2025-08-03 19:59:42.764227	0.65	4500.00
1183	\N	57	2024-11-25	9898.20	1	2025-08-03 19:59:42.99954	2025-08-03 19:59:42.99954	0.25	2503.66
1184	\N	57	2024-11-25	825.00	1	2025-08-03 19:59:43.224497	2025-08-03 19:59:43.224497	0.82	675.00
1185	\N	44	2024-11-26	3397.87	1	2025-08-03 19:59:43.600071	2025-08-03 19:59:43.600071	0.48	1643.33
1186	\N	44	2024-11-26	6523.22	1	2025-08-03 19:59:43.856069	2025-08-03 19:59:43.856069	0.60	3913.94
1187	\N	45	2024-11-26	8519.90	1	2025-08-03 19:59:44.113822	2025-08-03 19:59:44.113822	0.50	4219.90
1188	\N	172	2024-11-26	7380.00	1	2025-08-03 19:59:44.382867	2025-08-03 19:59:44.382867	0.50	3690.00
1189	\N	172	2024-11-26	5355.00	1	2025-08-03 19:59:44.637874	2025-08-03 19:59:44.637874	0.50	2677.50
1190	\N	172	2024-11-26	10030.00	1	2025-08-03 19:59:44.834093	2025-08-03 19:59:44.834093	0.50	5015.00
1191	\N	173	2024-11-26	5522.74	1	2025-08-03 19:59:45.257709	2025-08-03 19:59:45.257709	0.67	3699.94
1192	\N	57	2024-11-26	550.00	1	2025-08-03 19:59:45.473107	2025-08-03 19:59:45.473107	0.45	250.00
1193	\N	57	2024-11-26	1105.00	1	2025-08-03 19:59:45.715944	2025-08-03 19:59:45.715944	0.59	655.00
1194	\N	174	2024-11-26	11666.71	1	2025-08-03 19:59:46.098494	2025-08-03 19:59:46.098494	0.53	6150.00
1195	\N	53	2024-11-26	13455.00	1	2025-08-03 19:59:46.324956	2025-08-03 19:59:46.324956	0.39	5200.00
1196	\N	44	2024-11-27	2590.00	1	2025-08-03 19:59:46.523063	2025-08-03 19:59:46.523063	0.64	1659.66
1197	\N	44	2024-11-27	7230.00	1	2025-08-03 19:59:46.91913	2025-08-03 19:59:46.91913	0.60	4338.00
1198	\N	44	2024-11-27	1715.00	1	2025-08-03 19:59:47.150056	2025-08-03 19:59:47.150056	0.50	857.50
1199	\N	44	2024-11-27	3440.00	1	2025-08-03 19:59:47.389408	2025-08-03 19:59:47.389408	0.36	1248.66
1200	\N	105	2024-11-27	5965.00	1	2025-08-03 19:59:47.573158	2025-08-03 19:59:47.573158	0.67	4000.00
1201	\N	66	2024-11-27	9185.00	1	2025-08-03 19:59:47.806819	2025-08-03 19:59:47.806819	0.65	6000.00
1202	\N	66	2024-11-27	6185.00	1	2025-08-03 19:59:48.000242	2025-08-03 19:59:48.000242	0.41	2525.00
1203	\N	116	2024-11-27	7810.00	1	2025-08-03 19:59:48.300874	2025-08-03 19:59:48.300874	0.45	3535.22
1204	\N	60	2024-11-27	1480.00	1	2025-08-03 19:59:48.715347	2025-08-03 19:59:48.715347	0.50	740.00
1205	\N	53	2024-11-27	8355.00	1	2025-08-03 19:59:48.901234	2025-08-03 19:59:48.901234	0.45	3800.00
1206	\N	53	2024-11-27	7200.00	1	2025-08-03 19:59:49.138764	2025-08-03 19:59:49.138764	0.45	3250.00
1207	\N	44	2024-12-02	9393.90	1	2025-08-03 19:59:49.368135	2025-08-03 19:59:49.368135	0.37	3437.66
1208	\N	44	2024-12-02	4290.00	1	2025-08-03 19:59:49.595792	2025-08-03 19:59:49.595792	0.60	2574.00
1209	\N	44	2024-12-02	5592.24	1	2025-08-03 19:59:49.803784	2025-08-03 19:59:49.803784	0.60	3355.35
1210	\N	44	2024-12-02	7102.40	1	2025-08-03 19:59:50.040095	2025-08-03 19:59:50.040095	0.70	4971.80
1211	\N	44	2024-12-02	9175.00	1	2025-08-03 19:59:50.23823	2025-08-03 19:59:50.23823	0.55	5009.37
1212	\N	45	2024-12-02	6531.00	1	2025-08-03 19:59:50.444036	2025-08-03 19:59:50.444036	0.50	3265.50
1213	\N	45	2024-12-02	5562.16	1	2025-08-03 19:59:50.65773	2025-08-03 19:59:50.65773	0.50	2781.08
1214	\N	175	2024-12-02	7390.00	1	2025-08-03 19:59:51.045858	2025-08-03 19:59:51.045858	0.54	4000.00
1215	\N	88	2024-12-02	9339.52	1	2025-08-03 19:59:51.211847	2025-08-03 19:59:51.211847	0.75	7004.64
1216	\N	80	2024-12-02	11550.00	1	2025-08-03 19:59:51.38627	2025-08-03 19:59:51.38627	0.46	5270.36
1217	\N	83	2024-12-02	4155.32	1	2025-08-03 19:59:51.570728	2025-08-03 19:59:51.570728	0.50	2077.66
1218	\N	57	2024-12-02	1805.00	1	2025-08-03 19:59:51.749604	2025-08-03 19:59:51.749604	0.67	1205.00
1219	\N	57	2024-12-02	1105.00	1	2025-08-03 19:59:52.01161	2025-08-03 19:59:52.01161	0.55	605.00
1220	\N	53	2024-12-02	5368.25	1	2025-08-03 19:59:52.296174	2025-08-03 19:59:52.296174	0.75	4000.00
1221	\N	176	2024-12-02	840.00	1	2025-08-03 19:59:52.810467	2025-08-03 19:59:52.810467	0.00	0.00
1222	\N	88	2024-12-03	14710.00	1	2025-08-03 19:59:53.029296	2025-08-03 19:59:53.029296	0.63	9267.30
1223	\N	44	2024-12-03	8043.99	1	2025-08-03 19:59:53.398018	2025-08-03 19:59:53.398018	0.47	3804.17
1224	\N	44	2024-12-03	9110.37	1	2025-08-03 19:59:53.674432	2025-08-03 19:59:53.674432	0.60	5466.23
1225	\N	44	2024-12-03	3135.00	1	2025-08-03 19:59:53.953387	2025-08-03 19:59:53.953387	0.60	1881.00
1226	\N	44	2024-12-03	7025.47	1	2025-08-03 19:59:54.389396	2025-08-03 19:59:54.389396	0.45	3182.00
1227	\N	44	2024-12-03	1438.22	1	2025-08-03 19:59:54.686287	2025-08-03 19:59:54.686287	0.60	862.94
1228	\N	115	2024-12-03	10585.00	1	2025-08-03 19:59:54.9873	2025-08-03 19:59:54.9873	0.35	3704.75
1229	\N	175	2024-12-03	3840.00	1	2025-08-03 19:59:55.282038	2025-08-03 19:59:55.282038	0.26	1000.00
1230	\N	175	2024-12-03	2830.00	1	2025-08-03 19:59:55.656421	2025-08-03 19:59:55.656421	0.33	940.00
1231	\N	102	2024-12-03	8312.39	1	2025-08-03 19:59:55.941487	2025-08-03 19:59:55.941487	0.70	5818.67
1232	\N	116	2024-12-03	6020.00	1	2025-08-03 19:59:56.230663	2025-08-03 19:59:56.230663	0.52	3130.40
1233	\N	57	2024-12-03	3760.00	1	2025-08-03 19:59:56.516312	2025-08-03 19:59:56.516312	0.50	1880.00
1234	\N	44	2024-12-04	7169.04	1	2025-08-03 19:59:56.808436	2025-08-03 19:59:56.808436	0.51	3659.33
1235	\N	44	2024-12-04	8267.30	1	2025-08-03 19:59:57.108937	2025-08-03 19:59:57.108937	0.46	3828.00
1236	\N	44	2024-12-04	8960.99	1	2025-08-03 19:59:57.477804	2025-08-03 19:59:57.477804	0.46	4112.33
1237	\N	44	2024-12-04	11731.21	1	2025-08-03 19:59:57.780713	2025-08-03 19:59:57.780713	0.29	3404.34
1238	\N	44	2024-12-04	7421.21	1	2025-08-03 19:59:58.070093	2025-08-03 19:59:58.070093	0.70	5194.85
1239	\N	81	2024-12-04	10904.14	1	2025-08-03 19:59:58.369592	2025-08-03 19:59:58.369592	0.50	5452.07
1240	\N	80	2024-12-04	11285.00	1	2025-08-03 19:59:58.658873	2025-08-03 19:59:58.658873	0.55	6206.75
1241	\N	80	2024-12-04	11305.00	1	2025-08-03 19:59:58.962718	2025-08-03 19:59:58.962718	0.55	6217.75
1242	\N	48	2024-12-04	1650.00	1	2025-08-03 19:59:59.252037	2025-08-03 19:59:59.252037	0.65	1072.50
1243	\N	102	2024-12-04	6045.00	1	2025-08-03 19:59:59.534833	2025-08-03 19:59:59.534833	0.40	2418.00
1244	\N	110	2024-12-04	5600.00	1	2025-08-03 19:59:59.752532	2025-08-03 19:59:59.752532	0.55	3080.00
1245	\N	110	2024-12-04	9105.00	1	2025-08-03 20:00:00.012129	2025-08-03 20:00:00.012129	0.60	5463.00
1246	\N	126	2024-12-04	6280.00	1	2025-08-03 20:00:00.275981	2025-08-03 20:00:00.275981	0.65	4075.00
1247	\N	44	2024-12-05	6174.87	1	2025-08-03 20:00:00.556435	2025-08-03 20:00:00.556435	0.69	4236.38
1248	\N	44	2024-12-05	5034.15	1	2025-08-03 20:00:00.857871	2025-08-03 20:00:00.857871	0.54	2696.65
1249	\N	44	2024-12-05	5457.25	1	2025-08-03 20:00:01.103333	2025-08-03 20:00:01.103333	0.63	3457.25
1250	\N	96	2024-12-05	8345.00	1	2025-08-03 20:00:01.384321	2025-08-03 20:00:01.384321	0.50	4172.50
1251	\N	89	2024-12-05	7509.38	1	2025-08-03 20:00:01.658541	2025-08-03 20:00:01.658541	0.80	6007.51
1252	\N	89	2024-12-05	10610.00	1	2025-08-03 20:00:01.921292	2025-08-03 20:00:01.921292	0.61	6500.00
1253	\N	65	2024-12-05	6915.00	1	2025-08-03 20:00:02.202633	2025-08-03 20:00:02.202633	0.60	4149.00
1254	\N	102	2024-12-05	7380.00	1	2025-08-03 20:00:02.489539	2025-08-03 20:00:02.489539	0.75	5535.00
1255	\N	52	2024-12-05	4542.67	1	2025-08-03 20:00:02.772098	2025-08-03 20:00:02.772098	0.50	2271.00
1256	\N	44	2024-12-06	9712.99	1	2025-08-03 20:00:03.151165	2025-08-03 20:00:03.151165	0.70	6799.10
1257	\N	44	2024-12-06	10127.99	1	2025-08-03 20:00:03.462179	2025-08-03 20:00:03.462179	0.58	5840.43
1258	\N	44	2024-12-06	8895.00	1	2025-08-03 20:00:03.789244	2025-08-03 20:00:03.789244	0.70	6195.00
1259	\N	44	2024-12-06	2400.00	1	2025-08-03 20:00:04.055763	2025-08-03 20:00:04.055763	0.67	1600.00
1260	\N	44	2024-12-06	8790.00	1	2025-08-03 20:00:04.36242	2025-08-03 20:00:04.36242	0.70	6153.00
1261	\N	177	2024-12-06	10940.00	1	2025-08-03 20:00:04.874654	2025-08-03 20:00:04.874654	0.50	5470.00
1262	\N	105	2024-12-06	11285.00	1	2025-08-03 20:00:05.19459	2025-08-03 20:00:05.19459	0.50	5643.00
1263	\N	121	2024-12-06	1470.00	1	2025-08-03 20:00:05.480427	2025-08-03 20:00:05.480427	0.50	735.00
1264	\N	121	2024-12-06	2135.00	1	2025-08-03 20:00:05.76485	2025-08-03 20:00:05.76485	0.50	1067.50
1265	\N	121	2024-12-06	1755.00	1	2025-08-03 20:00:06.028858	2025-08-03 20:00:06.028858	0.50	877.50
1266	\N	178	2024-12-06	7745.00	1	2025-08-03 20:00:06.529779	2025-08-03 20:00:06.529779	0.67	5163.33
1267	\N	57	2024-12-06	1285.00	1	2025-08-03 20:00:06.840422	2025-08-03 20:00:06.840422	0.47	600.00
1268	\N	44	2024-12-09	9035.00	1	2025-08-03 20:00:07.145379	2025-08-03 20:00:07.145379	0.70	6324.50
1269	\N	44	2024-12-09	11406.63	1	2025-08-03 20:00:07.446405	2025-08-03 20:00:07.446405	0.70	7984.65
1270	\N	44	2024-12-09	10073.13	1	2025-08-03 20:00:07.753576	2025-08-03 20:00:07.753576	0.44	4444.00
1271	\N	44	2024-12-09	4575.00	1	2025-08-03 20:00:08.015014	2025-08-03 20:00:08.015014	0.70	3195.00
1272	\N	44	2024-12-09	7432.61	1	2025-08-03 20:00:08.31107	2025-08-03 20:00:08.31107	0.70	5202.83
1273	\N	102	2024-12-09	8465.00	1	2025-08-03 20:00:08.600143	2025-08-03 20:00:08.600143	0.75	6348.75
1274	\N	108	2024-12-09	9455.00	1	2025-08-03 20:00:09.001789	2025-08-03 20:00:09.001789	0.40	3782.00
1275	\N	108	2024-12-09	9542.60	1	2025-08-03 20:00:09.300034	2025-08-03 20:00:09.300034	0.40	3817.04
1276	\N	60	2024-12-09	1655.00	1	2025-08-03 20:00:09.701979	2025-08-03 20:00:09.701979	0.65	1075.75
1277	\N	179	2024-12-10	7915.00	1	2025-08-03 20:00:10.220385	2025-08-03 20:00:10.220385	0.44	3500.00
1278	\N	44	2024-12-10	4965.00	1	2025-08-03 20:00:10.562378	2025-08-03 20:00:10.562378	0.63	3124.00
1279	\N	44	2024-12-10	6689.89	1	2025-08-03 20:00:10.918488	2025-08-03 20:00:10.918488	0.70	4682.93
1280	\N	44	2024-12-10	6913.96	1	2025-08-03 20:00:11.209091	2025-08-03 20:00:11.209091	0.70	4839.78
1281	\N	44	2024-12-10	9633.63	1	2025-08-03 20:00:11.509858	2025-08-03 20:00:11.509858	0.46	4388.28
1282	\N	44	2024-12-10	7190.00	1	2025-08-03 20:00:11.939044	2025-08-03 20:00:11.939044	0.61	4382.66
1283	\N	44	2024-12-10	6750.51	1	2025-08-03 20:00:12.184778	2025-08-03 20:00:12.184778	0.60	4050.00
1284	\N	45	2024-12-10	8470.00	1	2025-08-03 20:00:12.520099	2025-08-03 20:00:12.520099	0.50	4235.00
1285	\N	65	2024-12-10	5990.00	1	2025-08-03 20:00:12.904106	2025-08-03 20:00:12.904106	0.55	3294.50
1286	\N	55	2024-12-10	1900.00	1	2025-08-03 20:00:13.202262	2025-08-03 20:00:13.202262	0.40	765.52
1287	\N	55	2024-12-10	1695.00	1	2025-08-03 20:00:13.471831	2025-08-03 20:00:13.471831	0.44	748.58
1288	\N	102	2024-12-10	3820.00	1	2025-08-03 20:00:13.770566	2025-08-03 20:00:13.770566	0.75	2865.00
1289	\N	180	2024-12-10	4700.00	1	2025-08-03 20:00:14.274411	2025-08-03 20:00:14.274411	0.91	4300.00
1290	\N	180	2024-12-10	11980.00	1	2025-08-03 20:00:14.67463	2025-08-03 20:00:14.67463	0.39	4623.70
1291	\N	52	2024-12-10	6385.00	1	2025-08-03 20:00:15.038139	2025-08-03 20:00:15.038139	0.50	3192.50
1292	\N	57	2024-12-10	2874.85	1	2025-08-03 20:00:15.331979	2025-08-03 20:00:15.331979	0.67	1924.85
1293	\N	53	2024-12-10	8271.56	1	2025-08-03 20:00:15.634251	2025-08-03 20:00:15.634251	0.73	6000.00
1294	\N	44	2024-12-11	1905.00	1	2025-08-03 20:00:16.033132	2025-08-03 20:00:16.033132	0.70	1333.50
1295	\N	44	2024-12-11	8825.00	1	2025-08-03 20:00:16.292149	2025-08-03 20:00:16.292149	0.60	5295.00
1296	\N	44	2024-12-11	5955.00	1	2025-08-03 20:00:16.603166	2025-08-03 20:00:16.603166	0.41	2462.66
1297	\N	44	2024-12-11	3390.00	1	2025-08-03 20:00:16.905676	2025-08-03 20:00:16.905676	0.70	2373.00
1298	\N	181	2024-12-11	7245.00	1	2025-08-03 20:00:17.573742	2025-08-03 20:00:17.573742	0.70	5071.50
1299	\N	45	2024-12-11	4205.00	1	2025-08-03 20:00:17.922512	2025-08-03 20:00:17.922512	0.50	2102.50
1300	\N	45	2024-12-11	8465.00	1	2025-08-03 20:00:18.205116	2025-08-03 20:00:18.205116	0.50	4232.50
1301	\N	80	2024-12-11	6170.00	1	2025-08-03 20:00:18.623459	2025-08-03 20:00:18.623459	0.55	3393.50
1302	\N	65	2024-12-11	12625.00	1	2025-08-03 20:00:18.998102	2025-08-03 20:00:18.998102	0.50	6312.50
1303	\N	116	2024-12-11	10215.00	1	2025-08-03 20:00:19.28835	2025-08-03 20:00:19.28835	0.33	3370.95
1304	\N	116	2024-12-11	7760.00	1	2025-08-03 20:00:19.575038	2025-08-03 20:00:19.575038	0.45	3492.00
1305	\N	60	2024-12-11	1920.00	1	2025-08-03 20:00:19.811889	2025-08-03 20:00:19.811889	0.70	1344.00
1306	\N	53	2024-12-11	3485.00	1	2025-08-03 20:00:20.088077	2025-08-03 20:00:20.088077	0.50	1750.00
1307	\N	44	2024-12-12	5200.00	1	2025-08-03 20:00:20.446001	2025-08-03 20:00:20.446001	0.70	3640.00
1308	\N	44	2024-12-12	4670.00	1	2025-08-03 20:00:20.722935	2025-08-03 20:00:20.722935	0.65	3015.16
1309	\N	44	2024-12-12	13426.48	1	2025-08-03 20:00:21.006382	2025-08-03 20:00:21.006382	0.49	6552.16
1310	\N	44	2024-12-12	11180.00	1	2025-08-03 20:00:21.265356	2025-08-03 20:00:21.265356	0.38	4245.50
1311	\N	44	2024-12-12	3691.43	1	2025-08-03 20:00:21.54694	2025-08-03 20:00:21.54694	0.70	2584.01
1312	\N	45	2024-12-12	12160.00	1	2025-08-03 20:00:21.828002	2025-08-03 20:00:21.828002	0.50	6080.00
1313	\N	45	2024-12-13	8579.19	1	2025-08-03 20:00:22.113891	2025-08-03 20:00:22.113891	0.50	4289.60
1314	\N	80	2024-12-13	7164.99	1	2025-08-03 20:00:22.419453	2025-08-03 20:00:22.419453	0.50	3584.00
1315	\N	80	2024-12-13	6720.00	1	2025-08-03 20:00:22.663802	2025-08-03 20:00:22.663802	0.80	5376.00
1316	\N	66	2024-12-13	8360.00	1	2025-08-03 20:00:23.009132	2025-08-03 20:00:23.009132	0.60	5016.00
1317	\N	55	2024-12-13	4730.00	1	2025-08-03 20:00:23.340598	2025-08-03 20:00:23.340598	0.34	1630.00
1318	\N	57	2024-12-13	6505.00	1	2025-08-03 20:00:23.696831	2025-08-03 20:00:23.696831	0.44	2885.00
1319	\N	44	2024-12-16	9430.00	1	2025-08-03 20:00:24.035101	2025-08-03 20:00:24.035101	0.70	6594.49
1320	\N	44	2024-12-16	3040.00	1	2025-08-03 20:00:24.336006	2025-08-03 20:00:24.336006	0.57	1730.81
1321	\N	45	2024-12-16	10303.47	1	2025-08-03 20:00:24.673061	2025-08-03 20:00:24.673061	0.50	5151.50
1322	\N	65	2024-12-16	6480.00	1	2025-08-03 20:00:25.009397	2025-08-03 20:00:25.009397	0.50	3240.00
1323	\N	102	2024-12-16	7761.35	1	2025-08-03 20:00:25.34407	2025-08-03 20:00:25.34407	0.50	3880.68
1324	\N	102	2024-12-16	4885.00	1	2025-08-03 20:00:25.670114	2025-08-03 20:00:25.670114	0.50	2442.50
1325	\N	102	2024-12-16	5300.00	1	2025-08-03 20:00:25.975751	2025-08-03 20:00:25.975751	0.60	3180.00
1326	\N	102	2024-12-16	33565.00	1	2025-08-03 20:00:26.260602	2025-08-03 20:00:26.260602	0.50	16782.50
1327	\N	84	2024-12-16	6865.00	1	2025-08-03 20:00:26.531683	2025-08-03 20:00:26.531683	0.58	4000.00
1328	\N	44	2024-12-17	7776.72	1	2025-08-03 20:00:26.804982	2025-08-03 20:00:26.804982	0.32	2522.33
1329	\N	44	2024-12-17	7100.00	1	2025-08-03 20:00:27.081208	2025-08-03 20:00:27.081208	0.65	4600.00
1330	\N	44	2024-12-17	9428.81	1	2025-08-03 20:00:27.404835	2025-08-03 20:00:27.404835	0.24	2266.78
1331	\N	45	2024-12-17	8395.00	1	2025-08-03 20:00:27.72774	2025-08-03 20:00:27.72774	0.43	3587.22
1332	\N	165	2024-12-17	13485.00	1	2025-08-03 20:00:28.028216	2025-08-03 20:00:28.028216	0.60	8091.00
1333	\N	80	2024-12-17	7135.90	1	2025-08-03 20:00:28.350084	2025-08-03 20:00:28.350084	0.60	4281.54
1334	\N	65	2024-12-17	10865.00	1	2025-08-03 20:00:28.698936	2025-08-03 20:00:28.698936	0.45	4889.25
1335	\N	48	2024-12-17	10020.00	1	2025-08-03 20:00:29.015264	2025-08-03 20:00:29.015264	0.40	4000.00
1336	\N	124	2024-12-17	11145.00	1	2025-08-03 20:00:29.296156	2025-08-03 20:00:29.296156	0.70	7801.50
1337	\N	110	2024-12-17	4085.00	1	2025-08-03 20:00:29.515002	2025-08-03 20:00:29.515002	0.59	2430.00
1338	\N	110	2024-12-17	7130.00	1	2025-08-03 20:00:29.786405	2025-08-03 20:00:29.786405	0.74	5273.55
1339	\N	52	2024-12-17	11650.00	1	2025-08-03 20:00:30.059724	2025-08-03 20:00:30.059724	0.50	5825.00
1340	\N	182	2024-12-17	8470.00	1	2025-08-03 20:00:30.567066	2025-08-03 20:00:30.567066	0.60	5082.00
1341	\N	182	2024-12-17	3485.00	1	2025-08-03 20:00:30.844448	2025-08-03 20:00:30.844448	0.65	2265.25
1342	\N	43	2024-12-18	6002.20	1	2025-08-03 20:00:31.114694	2025-08-03 20:00:31.114694	0.60	3592.00
1343	\N	43	2024-12-18	8030.00	1	2025-08-03 20:00:31.383057	2025-08-03 20:00:31.383057	0.52	4200.00
1344	\N	44	2024-12-18	11062.73	1	2025-08-03 20:00:31.658779	2025-08-03 20:00:31.658779	0.55	6080.00
1345	\N	44	2024-12-18	9234.27	1	2025-08-03 20:00:31.929	2025-08-03 20:00:31.929	0.61	5636.36
1346	\N	44	2024-12-18	8316.25	1	2025-08-03 20:00:32.211499	2025-08-03 20:00:32.211499	0.70	5821.38
1347	\N	44	2024-12-18	11731.21	1	2025-08-03 20:00:32.473577	2025-08-03 20:00:32.473577	0.26	3000.00
1348	\N	44	2024-12-18	12816.45	1	2025-08-03 20:00:32.743497	2025-08-03 20:00:32.743497	0.52	6721.18
1349	\N	44	2024-12-18	10838.79	1	2025-08-03 20:00:33.021873	2025-08-03 20:00:33.021873	0.25	2755.45
1350	\N	45	2024-12-18	10720.00	1	2025-08-03 20:00:33.292538	2025-08-03 20:00:33.292538	0.50	5360.00
1351	\N	88	2024-12-18	7757.65	1	2025-08-03 20:00:33.74445	2025-08-03 20:00:33.74445	0.52	4033.98
1352	\N	66	2024-12-18	11256.71	1	2025-08-03 20:00:34.03315	2025-08-03 20:00:34.03315	0.55	6191.19
1353	\N	154	2024-12-18	6655.00	1	2025-08-03 20:00:34.308352	2025-08-03 20:00:34.308352	0.45	3000.00
1354	\N	84	2024-12-18	4730.00	1	2025-08-03 20:00:34.570682	2025-08-03 20:00:34.570682	0.72	3426.70
1355	\N	44	2024-12-19	7035.00	1	2025-08-03 20:00:34.796648	2025-08-03 20:00:34.796648	0.70	4924.50
1356	\N	44	2024-12-19	9939.81	1	2025-08-03 20:00:35.076305	2025-08-03 20:00:35.076305	0.33	3238.33
1357	\N	44	2024-12-19	6780.25	1	2025-08-03 20:00:35.289702	2025-08-03 20:00:35.289702	0.32	2166.10
1358	\N	80	2024-12-19	11140.00	1	2025-08-03 20:00:35.583724	2025-08-03 20:00:35.583724	0.65	7241.00
1359	\N	124	2024-12-19	5640.00	1	2025-08-03 20:00:35.937329	2025-08-03 20:00:35.937329	0.50	2820.00
1360	\N	102	2024-12-19	5493.50	1	2025-08-03 20:00:36.239104	2025-08-03 20:00:36.239104	0.65	3570.78
1361	\N	52	2024-12-19	12197.62	1	2025-08-03 20:00:36.51217	2025-08-03 20:00:36.51217	0.50	6100.00
1362	\N	52	2024-12-19	11600.28	1	2025-08-03 20:00:36.778517	2025-08-03 20:00:36.778517	0.50	5800.00
1363	\N	44	2024-12-20	2310.00	1	2025-08-03 20:00:37.053988	2025-08-03 20:00:37.053988	0.70	1617.00
1364	\N	44	2024-12-20	4190.00	1	2025-08-03 20:00:37.430701	2025-08-03 20:00:37.430701	0.69	2890.00
1365	\N	44	2024-12-20	2540.00	1	2025-08-03 20:00:37.702118	2025-08-03 20:00:37.702118	0.60	1524.00
1366	\N	101	2024-12-20	4630.00	1	2025-08-03 20:00:38.020789	2025-08-03 20:00:38.020789	0.60	2778.00
1367	\N	96	2024-12-20	7267.90	1	2025-08-03 20:00:38.398005	2025-08-03 20:00:38.398005	0.35	2543.77
1368	\N	88	2024-12-20	9550.00	1	2025-08-03 20:00:38.743476	2025-08-03 20:00:38.743476	0.76	7258.00
1369	\N	48	2024-12-20	4970.00	1	2025-08-03 20:00:39.017478	2025-08-03 20:00:39.017478	0.65	3225.00
1370	\N	48	2024-12-20	5520.55	1	2025-08-03 20:00:39.315956	2025-08-03 20:00:39.315956	0.68	3775.00
1371	\N	55	2024-12-20	2325.00	1	2025-08-03 20:00:39.730468	2025-08-03 20:00:39.730468	0.55	1278.75
1372	\N	55	2024-12-20	11465.41	1	2025-08-03 20:00:40.007701	2025-08-03 20:00:40.007701	0.32	3640.41
1373	\N	102	2024-12-20	5825.00	1	2025-08-03 20:00:40.347555	2025-08-03 20:00:40.347555	0.70	4077.50
1374	\N	44	2024-12-23	7645.00	1	2025-08-03 20:00:40.676825	2025-08-03 20:00:40.676825	0.52	4000.00
1375	\N	44	2024-12-23	9864.92	1	2025-08-03 20:00:41.002191	2025-08-03 20:00:41.002191	0.61	5986.33
1376	\N	44	2024-12-23	5381.82	1	2025-08-03 20:00:41.291147	2025-08-03 20:00:41.291147	0.70	3767.28
1377	\N	45	2024-12-23	4590.00	1	2025-08-03 20:00:41.555089	2025-08-03 20:00:41.555089	0.50	2295.00
1378	\N	88	2024-12-23	9440.00	1	2025-08-03 20:00:41.788304	2025-08-03 20:00:41.788304	0.24	2265.60
1379	\N	86	2024-12-23	6865.00	1	2025-08-03 20:00:42.057757	2025-08-03 20:00:42.057757	0.67	4599.55
1380	\N	183	2024-12-23	16010.00	1	2025-08-03 20:00:42.495399	2025-08-03 20:00:42.495399	0.67	10672.00
1381	\N	183	2024-12-23	11715.00	1	2025-08-03 20:00:42.748894	2025-08-03 20:00:42.748894	0.68	8000.00
1382	\N	55	2024-12-23	2570.00	1	2025-08-03 20:00:43.055066	2025-08-03 20:00:43.055066	0.51	1308.45
1383	\N	110	2024-12-23	8535.00	1	2025-08-03 20:00:43.338846	2025-08-03 20:00:43.338846	0.55	4694.25
1384	\N	57	2024-12-23	6105.00	1	2025-08-03 20:00:43.606626	2025-08-03 20:00:43.606626	0.51	3130.77
1385	\N	184	2024-12-24	4655.00	1	2025-08-03 20:00:44.082588	2025-08-03 20:00:44.082588	0.00	0.00
1386	\N	52	2024-12-24	6298.27	1	2025-08-03 20:00:44.366292	2025-08-03 20:00:44.366292	0.50	3150.00
1387	\N	44	2024-12-27	10830.00	1	2025-08-03 20:00:44.637115	2025-08-03 20:00:44.637115	0.70	7530.00
1388	\N	165	2024-12-27	6225.00	1	2025-08-03 20:00:44.874109	2025-08-03 20:00:44.874109	0.55	3423.75
1389	\N	66	2024-12-27	4350.00	1	2025-08-03 20:00:45.161925	2025-08-03 20:00:45.161925	0.50	2175.00
1390	\N	102	2024-12-27	11799.85	1	2025-08-03 20:00:45.457647	2025-08-03 20:00:45.457647	0.65	7669.90
1391	\N	110	2024-12-27	6930.00	1	2025-08-03 20:00:45.823654	2025-08-03 20:00:45.823654	0.59	4087.57
1392	\N	110	2024-12-27	5965.00	1	2025-08-03 20:00:46.110012	2025-08-03 20:00:46.110012	0.50	2982.50
1393	\N	57	2024-12-27	2645.00	1	2025-08-03 20:00:46.383327	2025-08-03 20:00:46.383327	0.64	1695.00
1394	\N	44	2024-12-30	7476.75	1	2025-08-03 20:00:46.752748	2025-08-03 20:00:46.752748	0.44	3272.26
1395	\N	44	2024-12-30	4965.47	1	2025-08-03 20:00:47.049751	2025-08-03 20:00:47.049751	0.60	2979.29
1396	\N	44	2024-12-30	7915.00	1	2025-08-03 20:00:47.454801	2025-08-03 20:00:47.454801	0.25	1944.66
1397	\N	44	2024-12-30	3982.51	1	2025-08-03 20:00:47.744815	2025-08-03 20:00:47.744815	0.30	1179.50
1398	\N	44	2024-12-30	8391.68	1	2025-08-03 20:00:48.025504	2025-08-03 20:00:48.025504	0.82	6915.43
1399	\N	45	2024-12-30	8516.30	1	2025-08-03 20:00:48.328604	2025-08-03 20:00:48.328604	0.35	3000.00
1400	\N	185	2024-12-30	4985.00	1	2025-08-03 20:00:48.822022	2025-08-03 20:00:48.822022	0.65	3240.25
1401	\N	55	2024-12-30	3614.78	1	2025-08-03 20:00:49.226066	2025-08-03 20:00:49.226066	0.60	2168.86
1402	\N	110	2024-12-30	13945.00	1	2025-08-03 20:00:49.530143	2025-08-03 20:00:49.530143	0.50	6972.50
1403	\N	52	2024-12-30	8094.89	1	2025-08-03 20:00:49.813159	2025-08-03 20:00:49.813159	0.52	4227.00
1404	\N	60	2024-12-30	8600.40	1	2025-08-03 20:00:50.098315	2025-08-03 20:00:50.098315	0.67	5762.27
1405	\N	53	2024-12-30	7050.70	1	2025-08-03 20:00:50.347	2025-08-03 20:00:50.347	0.69	4900.00
1406	\N	123	2024-12-30	5055.00	1	2025-08-03 20:00:50.581176	2025-08-03 20:00:50.581176	0.50	2527.50
1407	\N	123	2024-12-30	3340.00	1	2025-08-03 20:00:50.780287	2025-08-03 20:00:50.780287	0.50	1670.00
1408	\N	44	2024-12-31	8570.00	1	2025-08-03 20:00:51.022826	2025-08-03 20:00:51.022826	0.70	5999.00
1409	\N	44	2024-12-31	4760.00	1	2025-08-03 20:00:51.275852	2025-08-03 20:00:51.275852	0.60	2856.00
1410	\N	44	2024-12-31	10969.84	1	2025-08-03 20:00:51.531798	2025-08-03 20:00:51.531798	0.58	6336.75
1411	\N	44	2024-12-31	6934.86	1	2025-08-03 20:00:51.793281	2025-08-03 20:00:51.793281	0.70	4854.41
1412	\N	44	2024-12-31	4972.04	1	2025-08-03 20:00:52.048053	2025-08-03 20:00:52.048053	0.36	1780.24
1413	\N	44	2024-12-31	1110.00	1	2025-08-03 20:00:52.259074	2025-08-03 20:00:52.259074	0.70	777.00
1414	\N	44	2024-12-31	5859.71	1	2025-08-03 20:00:52.628584	2025-08-03 20:00:52.628584	0.60	3515.83
1415	\N	44	2024-12-31	7390.00	1	2025-08-03 20:00:52.874982	2025-08-03 20:00:52.874982	0.70	5173.00
1416	\N	55	2024-12-31	4019.06	1	2025-08-03 20:00:53.088629	2025-08-03 20:00:53.088629	0.52	2100.00
1417	\N	44	2025-01-02	6052.15	1	2025-08-03 20:00:53.330415	2025-08-03 20:00:53.330415	0.45	2700.00
1418	\N	44	2025-01-02	10861.06	1	2025-08-03 20:00:53.591637	2025-08-03 20:00:53.591637	0.49	5300.00
1419	\N	44	2025-01-02	7258.49	1	2025-08-03 20:00:53.852666	2025-08-03 20:00:53.852666	0.56	4042.87
1420	\N	44	2025-01-02	12154.04	1	2025-08-03 20:00:54.101841	2025-08-03 20:00:54.101841	0.50	6076.66
1421	\N	44	2025-01-02	8391.68	1	2025-08-03 20:00:54.32574	2025-08-03 20:00:54.32574	0.60	5035.01
1422	\N	71	2025-01-02	14795.00	1	2025-08-03 20:00:54.695594	2025-08-03 20:00:54.695594	0.56	8219.44
1423	\N	88	2025-01-02	9350.00	1	2025-08-03 20:00:55.017774	2025-08-03 20:00:55.017774	0.53	4955.50
1424	\N	186	2025-01-02	3275.00	1	2025-08-03 20:00:55.47153	2025-08-03 20:00:55.47153	0.50	1637.50
1425	\N	109	2025-01-02	1425.00	1	2025-08-03 20:00:55.675147	2025-08-03 20:00:55.675147	0.49	700.00
1426	\N	108	2025-01-02	9117.74	1	2025-08-03 20:00:55.925273	2025-08-03 20:00:55.925273	0.50	4558.85
1427	\N	52	2025-01-02	2203.50	1	2025-08-03 20:00:56.174601	2025-08-03 20:00:56.174601	0.50	1101.75
1428	\N	116	2025-01-02	4750.00	1	2025-08-03 20:00:56.417935	2025-08-03 20:00:56.417935	0.50	2375.00
1429	\N	57	2025-01-02	2339.07	1	2025-08-03 20:00:56.679321	2025-08-03 20:00:56.679321	0.45	1050.00
1430	\N	57	2025-01-02	3315.00	1	2025-08-03 20:00:56.978191	2025-08-03 20:00:56.978191	0.67	2215.00
1431	\N	53	2025-01-02	6695.32	1	2025-08-03 20:00:57.224306	2025-08-03 20:00:57.224306	0.67	4485.00
1432	\N	44	2025-01-03	7935.00	1	2025-08-03 20:00:57.481224	2025-08-03 20:00:57.481224	0.70	5554.50
1433	\N	44	2025-01-03	11343.65	1	2025-08-03 20:00:57.729818	2025-08-03 20:00:57.729818	0.47	5316.66
1434	\N	44	2025-01-03	7265.00	1	2025-08-03 20:00:57.980864	2025-08-03 20:00:57.980864	0.50	3632.50
1435	\N	44	2025-01-03	11149.52	1	2025-08-03 20:00:58.244083	2025-08-03 20:00:58.244083	0.70	7804.67
1436	\N	44	2025-01-03	9861.30	1	2025-08-03 20:00:58.446209	2025-08-03 20:00:58.446209	0.58	5728.66
1437	\N	44	2025-01-03	10367.10	1	2025-08-03 20:00:58.693149	2025-08-03 20:00:58.693149	0.62	6437.06
1438	\N	88	2025-01-03	9765.00	1	2025-08-03 20:00:58.94538	2025-08-03 20:00:58.94538	0.26	2500.00
1439	\N	94	2025-01-03	10521.36	1	2025-08-03 20:00:59.19234	2025-08-03 20:00:59.19234	0.63	6586.46
1440	\N	187	2025-01-03	7515.00	1	2025-08-03 20:00:59.634787	2025-08-03 20:00:59.634787	0.55	4100.00
1441	\N	154	2025-01-03	6150.00	1	2025-08-03 20:00:59.838334	2025-08-03 20:00:59.838334	0.49	3000.00
1442	\N	108	2025-01-03	7206.97	1	2025-08-03 20:01:00.199362	2025-08-03 20:01:00.199362	0.50	3603.45
1443	\N	87	2025-01-03	9745.00	1	2025-08-03 20:01:00.434419	2025-08-03 20:01:00.434419	0.60	5847.00
1444	\N	87	2025-01-03	4380.00	1	2025-08-03 20:01:00.801323	2025-08-03 20:01:00.801323	0.36	1558.50
1445	\N	87	2025-01-03	6705.00	1	2025-08-03 20:01:01.05307	2025-08-03 20:01:01.05307	0.50	3352.50
1446	\N	45	2025-01-06	6350.00	1	2025-08-03 20:01:01.426264	2025-08-03 20:01:01.426264	0.50	3175.00
1447	\N	45	2025-01-06	10765.90	1	2025-08-03 20:01:01.684141	2025-08-03 20:01:01.684141	0.50	5382.50
1448	\N	80	2025-01-06	1405.00	1	2025-08-03 20:01:01.936733	2025-08-03 20:01:01.936733	0.58	812.57
1449	\N	109	2025-01-06	2050.00	1	2025-08-03 20:01:02.135359	2025-08-03 20:01:02.135359	0.30	620.00
1450	\N	110	2025-01-06	8305.00	1	2025-08-03 20:01:02.336866	2025-08-03 20:01:02.336866	0.60	4983.00
1451	\N	44	2025-01-07	9876.75	1	2025-08-03 20:01:02.655538	2025-08-03 20:01:02.655538	0.64	6272.33
1452	\N	71	2025-01-07	10598.34	1	2025-08-03 20:01:02.900815	2025-08-03 20:01:02.900815	0.50	5299.17
1453	\N	188	2025-01-07	10530.00	1	2025-08-03 20:01:03.326985	2025-08-03 20:01:03.326985	0.33	3478.23
1454	\N	80	2025-01-07	4120.00	1	2025-08-03 20:01:03.545036	2025-08-03 20:01:03.545036	0.50	2060.00
1455	\N	110	2025-01-07	6390.00	1	2025-08-03 20:01:03.790024	2025-08-03 20:01:03.790024	0.65	4153.50
1456	\N	57	2025-01-07	18515.00	1	2025-08-03 20:01:04.122824	2025-08-03 20:01:04.122824	0.46	8500.00
1457	\N	44	2025-01-08	8125.32	1	2025-08-03 20:01:04.378037	2025-08-03 20:01:04.378037	0.25	2000.00
1458	\N	44	2025-01-08	4775.00	1	2025-08-03 20:01:04.872938	2025-08-03 20:01:04.872938	0.60	2865.00
1459	\N	44	2025-01-08	2695.14	1	2025-08-03 20:01:05.142011	2025-08-03 20:01:05.142011	0.60	1617.09
1460	\N	44	2025-01-08	8105.00	1	2025-08-03 20:01:05.391254	2025-08-03 20:01:05.391254	0.46	3741.80
1461	\N	44	2025-01-08	7459.72	1	2025-08-03 20:01:05.641028	2025-08-03 20:01:05.641028	0.69	5159.72
1462	\N	44	2025-01-08	9255.00	1	2025-08-03 20:01:05.891173	2025-08-03 20:01:05.891173	0.49	4539.94
1463	\N	189	2025-01-08	9452.89	1	2025-08-03 20:01:06.279021	2025-08-03 20:01:06.279021	0.42	4000.00
1464	\N	165	2025-01-08	8925.00	1	2025-08-03 20:01:06.597286	2025-08-03 20:01:06.597286	0.50	4462.50
1465	\N	190	2025-01-08	10270.00	1	2025-08-03 20:01:07.024334	2025-08-03 20:01:07.024334	0.50	5135.00
1466	\N	93	2025-01-08	7280.00	1	2025-08-03 20:01:07.286835	2025-08-03 20:01:07.286835	0.49	3560.54
1467	86	48	2025-01-08	7405.00	1	2025-08-03 20:01:07.543434	2025-08-03 20:01:07.543434	0.00	0.00
1468	\N	84	2025-01-08	6631.93	1	2025-08-03 20:01:07.810309	2025-08-03 20:01:07.810309	0.71	4708.67
1469	\N	52	2025-01-08	1585.00	1	2025-08-03 20:01:08.006833	2025-08-03 20:01:08.006833	0.50	792.50
1470	\N	53	2025-01-08	4250.94	1	2025-08-03 20:01:08.262501	2025-08-03 20:01:08.262501	0.59	2500.00
1471	\N	44	2025-01-09	11185.00	1	2025-08-03 20:01:08.612887	2025-08-03 20:01:08.612887	0.59	6650.19
1472	\N	44	2025-01-09	9135.00	1	2025-08-03 20:01:08.981096	2025-08-03 20:01:08.981096	0.60	5481.00
1473	\N	44	2025-01-09	5630.00	1	2025-08-03 20:01:09.175567	2025-08-03 20:01:09.175567	0.54	3040.20
1474	\N	44	2025-01-09	6925.00	1	2025-08-03 20:01:09.359102	2025-08-03 20:01:09.359102	0.48	3327.36
1475	\N	44	2025-01-09	6925.00	1	2025-08-03 20:01:09.613334	2025-08-03 20:01:09.613334	0.48	3327.36
1476	\N	44	2025-01-09	645.00	1	2025-08-03 20:01:09.865399	2025-08-03 20:01:09.865399	0.70	451.50
1477	\N	44	2025-01-09	2578.75	1	2025-08-03 20:01:10.244593	2025-08-03 20:01:10.244593	0.74	1896.66
1478	\N	104	2025-01-09	2575.00	1	2025-08-03 20:01:10.523089	2025-08-03 20:01:10.523089	0.50	1287.50
1479	\N	104	2025-01-09	2635.00	1	2025-08-03 20:01:10.848397	2025-08-03 20:01:10.848397	0.50	1317.50
1480	\N	124	2025-01-09	7130.00	1	2025-08-03 20:01:11.215101	2025-08-03 20:01:11.215101	0.55	3921.50
1481	\N	116	2025-01-09	8510.39	1	2025-08-03 20:01:11.478559	2025-08-03 20:01:11.478559	0.35	2978.64
1482	\N	44	2025-01-10	6402.24	1	2025-08-03 20:01:11.681425	2025-08-03 20:01:11.681425	0.70	4481.57
1483	\N	44	2025-01-10	6650.00	1	2025-08-03 20:01:11.929111	2025-08-03 20:01:11.929111	0.60	3990.00
1484	\N	44	2025-01-10	4495.65	1	2025-08-03 20:01:12.14708	2025-08-03 20:01:12.14708	0.53	2400.00
1485	\N	44	2025-01-10	10713.62	1	2025-08-03 20:01:12.509763	2025-08-03 20:01:12.509763	0.59	6279.63
1486	\N	131	2025-01-10	10489.84	1	2025-08-03 20:01:12.761294	2025-08-03 20:01:12.761294	0.75	7867.38
1487	\N	102	2025-01-10	5085.00	1	2025-08-03 20:01:13.006003	2025-08-03 20:01:13.006003	0.75	3813.00
1488	\N	57	2025-01-10	10240.00	1	2025-08-03 20:01:13.386181	2025-08-03 20:01:13.386181	0.27	2789.00
1489	\N	60	2025-01-10	2290.00	1	2025-08-03 20:01:13.639506	2025-08-03 20:01:13.639506	0.10	229.00
1490	\N	60	2025-01-10	3330.00	1	2025-08-03 20:01:14.003084	2025-08-03 20:01:14.003084	0.19	641.46
1491	\N	53	2025-01-10	10090.74	1	2025-08-03 20:01:14.386157	2025-08-03 20:01:14.386157	0.40	4000.00
1492	\N	53	2025-01-10	6932.04	1	2025-08-03 20:01:14.660431	2025-08-03 20:01:14.660431	0.68	4700.00
1493	\N	44	2025-01-13	9400.57	1	2025-08-03 20:01:14.87314	2025-08-03 20:01:14.87314	0.32	2969.11
1494	\N	44	2025-01-13	5251.61	1	2025-08-03 20:01:15.115715	2025-08-03 20:01:15.115715	0.65	3426.28
1495	\N	44	2025-01-13	10611.46	1	2025-08-03 20:01:15.367844	2025-08-03 20:01:15.367844	0.52	5514.65
1496	\N	44	2025-01-13	880.00	1	2025-08-03 20:01:15.613825	2025-08-03 20:01:15.613825	0.50	440.00
1497	\N	44	2025-01-13	4680.00	1	2025-08-03 20:01:15.857527	2025-08-03 20:01:15.857527	0.70	3280.00
1498	\N	45	2025-01-13	1675.00	1	2025-08-03 20:01:16.107706	2025-08-03 20:01:16.107706	0.50	837.50
1499	\N	80	2025-01-13	12050.00	1	2025-08-03 20:01:16.363974	2025-08-03 20:01:16.363974	0.58	6989.00
1500	\N	116	2025-01-13	1910.00	1	2025-08-03 20:01:16.736323	2025-08-03 20:01:16.736323	0.51	974.10
1501	\N	57	2025-01-13	1000.00	1	2025-08-03 20:01:16.925656	2025-08-03 20:01:16.925656	0.60	600.00
1502	\N	60	2025-01-13	5124.01	1	2025-08-03 20:01:17.178331	2025-08-03 20:01:17.178331	0.60	3074.41
1503	\N	44	2025-01-14	8745.00	1	2025-08-03 20:01:17.433406	2025-08-03 20:01:17.433406	0.70	6121.50
1504	\N	44	2025-01-14	8051.51	1	2025-08-03 20:01:17.677719	2025-08-03 20:01:17.677719	0.70	5636.06
1505	\N	44	2025-01-14	1354.05	1	2025-08-03 20:01:17.933293	2025-08-03 20:01:17.933293	0.70	947.84
1506	\N	45	2025-01-14	8663.71	1	2025-08-03 20:01:18.316309	2025-08-03 20:01:18.316309	0.50	4331.85
1507	\N	45	2025-01-14	3820.00	1	2025-08-03 20:01:18.721378	2025-08-03 20:01:18.721378	0.50	1910.00
1508	\N	165	2025-01-14	7380.00	1	2025-08-03 20:01:18.912547	2025-08-03 20:01:18.912547	0.50	3690.00
1509	\N	66	2025-01-14	10455.00	1	2025-08-03 20:01:19.271905	2025-08-03 20:01:19.271905	0.85	8914.35
1510	\N	124	2025-01-14	4945.00	1	2025-08-03 20:01:19.522344	2025-08-03 20:01:19.522344	0.60	2967.00
1511	\N	102	2025-01-14	2995.00	1	2025-08-03 20:01:19.763959	2025-08-03 20:01:19.763959	0.70	2096.50
1512	\N	60	2025-01-14	8356.79	1	2025-08-03 20:01:20.011702	2025-08-03 20:01:20.011702	0.60	5014.08
1513	\N	123	2025-01-14	9730.00	1	2025-08-03 20:01:20.232374	2025-08-03 20:01:20.232374	0.36	3500.00
1514	\N	44	2025-01-15	10002.78	1	2025-08-03 20:01:20.486509	2025-08-03 20:01:20.486509	0.52	5207.59
1515	\N	44	2025-01-15	10455.00	1	2025-08-03 20:01:20.73072	2025-08-03 20:01:20.73072	0.50	5227.50
1516	\N	44	2025-01-15	3992.34	1	2025-08-03 20:01:20.98841	2025-08-03 20:01:20.98841	0.70	2794.64
1517	\N	191	2025-01-15	10607.67	1	2025-08-03 20:01:21.45017	2025-08-03 20:01:21.45017	0.50	5303.84
1518	\N	45	2025-01-15	1165.00	1	2025-08-03 20:01:21.691492	2025-08-03 20:01:21.691492	0.50	582.50
1519	\N	45	2025-01-15	8006.26	1	2025-08-03 20:01:21.954371	2025-08-03 20:01:21.954371	0.50	4003.13
1520	\N	44	2025-01-16	5025.00	1	2025-08-03 20:01:22.213028	2025-08-03 20:01:22.213028	0.60	2996.97
1521	\N	44	2025-01-16	6490.00	1	2025-08-03 20:01:22.408555	2025-08-03 20:01:22.408555	0.59	3811.72
1522	\N	44	2025-01-16	9839.43	1	2025-08-03 20:01:22.66347	2025-08-03 20:01:22.66347	0.66	6491.46
1523	\N	44	2025-01-16	4592.30	1	2025-08-03 20:01:22.89935	2025-08-03 20:01:22.89935	0.52	2405.57
1524	\N	44	2025-01-16	10975.84	1	2025-08-03 20:01:23.147419	2025-08-03 20:01:23.147419	0.64	7040.20
1525	\N	44	2025-01-16	12617.63	1	2025-08-03 20:01:23.382798	2025-08-03 20:01:23.382798	0.56	7040.20
1526	\N	44	2025-01-16	4887.62	1	2025-08-03 20:01:23.639799	2025-08-03 20:01:23.639799	0.53	2581.69
1527	\N	44	2025-01-16	6950.00	1	2025-08-03 20:01:23.876546	2025-08-03 20:01:23.876546	0.60	4145.06
1528	\N	192	2025-01-16	12604.60	1	2025-08-03 20:01:24.341286	2025-08-03 20:01:24.341286	0.49	6187.50
1529	\N	88	2025-01-16	9520.00	1	2025-08-03 20:01:24.556649	2025-08-03 20:01:24.556649	0.72	6854.40
1530	\N	88	2025-01-16	9910.00	1	2025-08-03 20:01:24.946744	2025-08-03 20:01:24.946744	0.70	6937.00
1531	\N	80	2025-01-16	10230.00	1	2025-08-03 20:01:25.22216	2025-08-03 20:01:25.22216	0.60	6138.00
1532	\N	65	2025-01-16	10186.78	1	2025-08-03 20:01:25.470119	2025-08-03 20:01:25.470119	0.60	6122.07
1533	\N	187	2025-01-16	10207.00	1	2025-08-03 20:01:25.679934	2025-08-03 20:01:25.679934	0.25	2551.75
1534	\N	193	2025-01-16	2275.00	1	2025-08-03 20:01:26.1194	2025-08-03 20:01:26.1194	0.65	1486.04
1535	\N	194	2025-01-16	12505.00	1	2025-08-03 20:01:26.667469	2025-08-03 20:01:26.667469	0.50	6252.50
1536	\N	116	2025-01-16	1415.00	1	2025-08-03 20:01:26.873988	2025-08-03 20:01:26.873988	0.55	778.25
1537	\N	57	2025-01-16	5006.62	1	2025-08-03 20:01:27.067374	2025-08-03 20:01:27.067374	0.60	3003.97
1538	\N	53	2025-01-16	4685.00	1	2025-08-03 20:01:27.425376	2025-08-03 20:01:27.425376	0.50	2350.00
1539	\N	44	2025-01-17	11717.06	1	2025-08-03 20:01:27.683126	2025-08-03 20:01:27.683126	0.58	6771.51
1540	\N	44	2025-01-17	3540.00	1	2025-08-03 20:01:27.92348	2025-08-03 20:01:27.92348	0.50	1770.00
1541	\N	44	2025-01-17	8673.25	1	2025-08-03 20:01:28.180015	2025-08-03 20:01:28.180015	0.27	2321.89
1542	\N	44	2025-01-17	1250.00	1	2025-08-03 20:01:28.384625	2025-08-03 20:01:28.384625	0.50	625.00
1543	\N	88	2025-01-17	2955.00	1	2025-08-03 20:01:28.75107	2025-08-03 20:01:28.75107	0.53	1576.00
1544	\N	102	2025-01-17	12484.00	1	2025-08-03 20:01:28.998195	2025-08-03 20:01:28.998195	0.42	5244.95
1545	\N	195	2025-01-17	10344.66	1	2025-08-03 20:01:29.55443	2025-08-03 20:01:29.55443	0.49	5089.28
1546	\N	51	2025-01-17	6190.00	1	2025-08-03 20:01:29.753408	2025-08-03 20:01:29.753408	0.33	2066.67
1547	\N	110	2025-01-17	7185.00	1	2025-08-03 20:01:29.999365	2025-08-03 20:01:29.999365	0.65	4670.25
1548	\N	53	2025-01-17	7904.96	1	2025-08-03 20:01:30.202165	2025-08-03 20:01:30.202165	0.51	4000.00
1549	\N	44	2025-01-20	9275.00	1	2025-08-03 20:01:30.44681	2025-08-03 20:01:30.44681	0.70	6535.33
1550	\N	44	2025-01-20	8024.75	1	2025-08-03 20:01:30.809608	2025-08-03 20:01:30.809608	0.81	6521.21
1551	\N	44	2025-01-20	10107.90	1	2025-08-03 20:01:31.134893	2025-08-03 20:01:31.134893	0.71	7159.09
1552	\N	44	2025-01-20	8640.00	1	2025-08-03 20:01:31.376749	2025-08-03 20:01:31.376749	0.64	5540.00
1553	\N	44	2025-01-20	9375.00	1	2025-08-03 20:01:31.636949	2025-08-03 20:01:31.636949	0.60	5625.00
1554	\N	88	2025-01-20	9285.00	1	2025-08-03 20:01:31.88423	2025-08-03 20:01:31.88423	0.43	4000.00
1555	\N	55	2025-01-20	5242.25	1	2025-08-03 20:01:32.141073	2025-08-03 20:01:32.141073	0.63	3302.25
1556	\N	55	2025-01-20	15928.61	1	2025-08-03 20:01:32.390852	2025-08-03 20:01:32.390852	0.48	7595.79
1557	\N	60	2025-01-20	6866.05	1	2025-08-03 20:01:32.616602	2025-08-03 20:01:32.616602	0.60	4119.63
1558	\N	60	2025-01-20	3615.00	1	2025-08-03 20:01:32.835661	2025-08-03 20:01:32.835661	0.50	1807.50
1559	\N	44	2025-01-21	1669.40	1	2025-08-03 20:01:33.204947	2025-08-03 20:01:33.204947	0.62	1036.66
1560	\N	44	2025-01-21	6930.00	1	2025-08-03 20:01:33.463238	2025-08-03 20:01:33.463238	0.33	2314.73
1561	\N	44	2025-01-21	6235.00	1	2025-08-03 20:01:33.669604	2025-08-03 20:01:33.669604	0.70	4364.50
1562	\N	44	2025-01-21	4945.00	1	2025-08-03 20:01:33.870998	2025-08-03 20:01:33.870998	0.36	1765.18
1563	\N	52	2025-01-21	2683.77	1	2025-08-03 20:01:34.123051	2025-08-03 20:01:34.123051	0.50	1343.00
1564	\N	44	2025-01-22	1675.00	1	2025-08-03 20:01:34.37924	2025-08-03 20:01:34.37924	0.70	1172.50
1565	\N	196	2025-01-22	1600.00	1	2025-08-03 20:01:34.801153	2025-08-03 20:01:34.801153	0.65	1040.00
1566	\N	196	2025-01-22	1600.00	1	2025-08-03 20:01:35.003091	2025-08-03 20:01:35.003091	0.65	1040.00
1567	\N	80	2025-01-22	1980.00	1	2025-08-03 20:01:35.208866	2025-08-03 20:01:35.208866	0.80	1584.00
1568	\N	124	2025-01-22	12780.00	1	2025-08-03 20:01:35.457249	2025-08-03 20:01:35.457249	0.65	8307.00
1569	\N	55	2025-01-22	4580.00	1	2025-08-03 20:01:35.707186	2025-08-03 20:01:35.707186	0.30	1374.00
1570	\N	123	2025-01-22	5835.00	1	2025-08-03 20:01:35.948434	2025-08-03 20:01:35.948434	0.40	2334.00
1571	\N	151	2025-01-23	11905.00	1	2025-08-03 20:01:36.198467	2025-08-03 20:01:36.198467	0.50	5952.50
1572	\N	71	2025-01-23	645.00	1	2025-08-03 20:01:36.44314	2025-08-03 20:01:36.44314	0.62	400.00
1573	\N	93	2025-01-23	1070.00	1	2025-08-03 20:01:36.64895	2025-08-03 20:01:36.64895	0.75	802.50
1574	\N	48	2025-01-23	6921.60	1	2025-08-03 20:01:36.894057	2025-08-03 20:01:36.894057	0.60	4152.96
1575	\N	55	2025-01-23	4814.60	1	2025-08-03 20:01:37.252587	2025-08-03 20:01:37.252587	0.58	2814.60
1576	\N	55	2025-01-23	8495.00	1	2025-08-03 20:01:37.501353	2025-08-03 20:01:37.501353	0.65	5495.00
1577	\N	53	2025-01-23	6440.00	1	2025-08-03 20:01:37.742289	2025-08-03 20:01:37.742289	0.62	4000.00
1578	\N	44	2025-01-24	8660.00	1	2025-08-03 20:01:37.936635	2025-08-03 20:01:37.936635	1.00	8660.00
1579	\N	44	2025-01-24	8660.00	1	2025-08-03 20:01:38.193748	2025-08-03 20:01:38.193748	0.70	6062.00
1580	\N	44	2025-01-24	4415.32	1	2025-08-03 20:01:38.450086	2025-08-03 20:01:38.450086	0.69	3065.32
1581	\N	44	2025-01-24	7915.00	1	2025-08-03 20:01:38.648953	2025-08-03 20:01:38.648953	0.26	2059.87
1582	\N	45	2025-01-24	5110.00	1	2025-08-03 20:01:38.882841	2025-08-03 20:01:38.882841	0.50	2555.00
1583	\N	197	2025-01-24	5595.00	1	2025-08-03 20:01:39.262642	2025-08-03 20:01:39.262642	0.27	1500.00
1584	\N	94	2025-01-24	2195.00	1	2025-08-03 20:01:39.470968	2025-08-03 20:01:39.470968	0.70	1536.50
1585	\N	55	2025-01-24	4023.00	1	2025-08-03 20:01:39.72115	2025-08-03 20:01:39.72115	0.52	2100.00
1586	\N	52	2025-01-24	6855.00	1	2025-08-03 20:01:39.98139	2025-08-03 20:01:39.98139	0.50	3427.50
1587	\N	52	2025-01-24	4000.00	1	2025-08-03 20:01:40.239993	2025-08-03 20:01:40.239993	0.50	2000.00
1588	\N	60	2025-01-24	9080.00	1	2025-08-03 20:01:40.48308	2025-08-03 20:01:40.48308	0.80	7264.00
1589	\N	176	2025-01-24	10406.51	1	2025-08-03 20:01:40.69638	2025-08-03 20:01:40.69638	0.50	5203.00
1590	\N	44	2025-01-27	2105.00	1	2025-08-03 20:01:41.063795	2025-08-03 20:01:41.063795	0.58	1217.63
1591	\N	44	2025-01-27	5080.00	1	2025-08-03 20:01:41.426384	2025-08-03 20:01:41.426384	0.55	2803.96
1592	\N	44	2025-01-27	10424.03	1	2025-08-03 20:01:41.680322	2025-08-03 20:01:41.680322	0.45	4709.66
1593	\N	44	2025-01-27	7195.00	1	2025-08-03 20:01:41.940373	2025-08-03 20:01:41.940373	0.50	3597.50
1594	\N	45	2025-01-27	6675.00	1	2025-08-03 20:01:42.204989	2025-08-03 20:01:42.204989	0.50	3337.50
1595	\N	71	2025-01-27	6872.18	1	2025-08-03 20:01:42.452835	2025-08-03 20:01:42.452835	0.60	4123.31
1596	\N	58	2025-01-27	13840.26	1	2025-08-03 20:01:42.707212	2025-08-03 20:01:42.707212	0.63	8728.86
1597	\N	198	2025-01-27	3375.00	1	2025-08-03 20:01:43.267347	2025-08-03 20:01:43.267347	0.65	2193.75
1598	\N	102	2025-01-27	2010.00	1	2025-08-03 20:01:43.454331	2025-08-03 20:01:43.454331	0.33	670.00
1599	\N	102	2025-01-27	1510.00	1	2025-08-03 20:01:43.831643	2025-08-03 20:01:43.831643	0.33	503.00
1600	\N	126	2025-01-27	10736.99	1	2025-08-03 20:01:44.092863	2025-08-03 20:01:44.092863	0.70	7500.00
1601	\N	126	2025-01-27	10858.99	1	2025-08-03 20:01:44.348534	2025-08-03 20:01:44.348534	0.70	7600.00
1602	\N	44	2025-01-28	9788.90	1	2025-08-03 20:01:44.608754	2025-08-03 20:01:44.608754	0.46	4529.63
1603	\N	44	2025-01-28	4565.92	1	2025-08-03 20:01:44.833508	2025-08-03 20:01:44.833508	0.60	2739.56
1604	\N	45	2025-01-28	9446.17	1	2025-08-03 20:01:45.084845	2025-08-03 20:01:45.084845	0.50	4723.08
1605	\N	48	2025-01-28	11465.00	1	2025-08-03 20:01:45.331903	2025-08-03 20:01:45.331903	0.59	6800.00
1606	\N	48	2025-01-28	15905.00	1	2025-08-03 20:01:45.582105	2025-08-03 20:01:45.582105	0.60	9500.00
1607	\N	102	2025-01-28	5840.00	1	2025-08-03 20:01:45.952303	2025-08-03 20:01:45.952303	0.50	2920.00
1608	\N	44	2025-01-29	6553.77	1	2025-08-03 20:01:46.178399	2025-08-03 20:01:46.178399	0.70	4587.64
1609	\N	44	2025-01-29	4285.00	1	2025-08-03 20:01:46.376208	2025-08-03 20:01:46.376208	0.43	1844.74
1610	\N	44	2025-01-29	7150.75	1	2025-08-03 20:01:46.641115	2025-08-03 20:01:46.641115	0.51	3617.60
1611	\N	45	2025-01-29	4335.00	1	2025-08-03 20:01:46.891993	2025-08-03 20:01:46.891993	0.23	1000.00
1612	\N	71	2025-01-29	1100.00	1	2025-08-03 20:01:47.250227	2025-08-03 20:01:47.250227	0.61	666.00
1613	\N	71	2025-01-29	4531.10	1	2025-08-03 20:01:47.496654	2025-08-03 20:01:47.496654	0.60	2718.60
1614	\N	80	2025-01-29	10745.00	1	2025-08-03 20:01:47.743333	2025-08-03 20:01:47.743333	0.65	6984.25
1615	\N	66	2025-01-29	12586.28	1	2025-08-03 20:01:48.112443	2025-08-03 20:01:48.112443	0.60	7551.77
1616	\N	132	2025-01-29	5710.00	1	2025-08-03 20:01:48.58837	2025-08-03 20:01:48.58837	0.70	3997.00
1617	\N	55	2025-01-29	6154.14	1	2025-08-03 20:01:48.839129	2025-08-03 20:01:48.839129	0.40	2439.11
1618	\N	116	2025-01-29	6745.00	1	2025-08-03 20:01:49.082015	2025-08-03 20:01:49.082015	0.55	3709.75
1619	\N	53	2025-01-29	4617.20	1	2025-08-03 20:01:49.320133	2025-08-03 20:01:49.320133	0.71	3300.00
1620	\N	53	2025-01-30	9641.63	1	2025-08-03 20:01:49.572005	2025-08-03 20:01:49.572005	0.67	6500.00
1621	\N	44	2025-01-30	33407.13	1	2025-08-03 20:01:49.852959	2025-08-03 20:01:49.852959	0.00	0.00
1622	\N	44	2025-01-30	2450.54	1	2025-08-03 20:01:50.117601	2025-08-03 20:01:50.117601	0.55	1347.80
1623	\N	44	2025-01-30	6615.00	1	2025-08-03 20:01:50.372672	2025-08-03 20:01:50.372672	0.70	4630.50
1624	\N	45	2025-01-30	5315.00	1	2025-08-03 20:01:50.567113	2025-08-03 20:01:50.567113	0.50	2657.50
1625	\N	80	2025-01-30	2125.00	1	2025-08-03 20:01:50.812142	2025-08-03 20:01:50.812142	0.45	950.00
1626	\N	55	2025-01-30	3789.93	1	2025-08-03 20:01:51.178939	2025-08-03 20:01:51.178939	0.42	1582.19
1627	\N	55	2025-01-30	2190.00	1	2025-08-03 20:01:51.442216	2025-08-03 20:01:51.442216	0.39	854.87
1628	\N	55	2025-01-30	5500.00	1	2025-08-03 20:01:51.643711	2025-08-03 20:01:51.643711	0.58	3212.78
1629	\N	55	2025-01-30	5299.30	1	2025-08-03 20:01:51.900542	2025-08-03 20:01:51.900542	0.44	2329.49
1630	\N	55	2025-01-30	2755.88	1	2025-08-03 20:01:52.152479	2025-08-03 20:01:52.152479	0.39	1086.61
1631	\N	110	2025-01-30	9325.00	1	2025-08-03 20:01:52.405337	2025-08-03 20:01:52.405337	0.54	5000.00
1632	\N	44	2025-01-31	4144.78	1	2025-08-03 20:01:52.774259	2025-08-03 20:01:52.774259	0.36	1481.33
1633	\N	44	2025-01-31	5837.15	1	2025-08-03 20:01:52.968858	2025-08-03 20:01:52.968858	0.23	1333.33
1634	\N	44	2025-01-31	6594.75	1	2025-08-03 20:01:53.213406	2025-08-03 20:01:53.213406	0.70	4616.33
1635	\N	44	2025-01-31	13464.32	1	2025-08-03 20:01:53.464652	2025-08-03 20:01:53.464652	0.64	8578.66
1636	\N	44	2025-01-31	4004.80	1	2025-08-03 20:01:53.662387	2025-08-03 20:01:53.662387	0.56	2229.52
1637	\N	165	2025-01-31	8265.00	1	2025-08-03 20:01:53.876502	2025-08-03 20:01:53.876502	0.50	4132.50
1638	\N	55	2025-01-31	3194.16	1	2025-08-03 20:01:54.064273	2025-08-03 20:01:54.064273	0.47	1500.00
1639	\N	52	2025-01-31	5060.00	1	2025-08-03 20:01:54.31753	2025-08-03 20:01:54.31753	0.50	2512.50
1640	\N	84	2025-02-03	1400.25	1	2025-08-03 20:01:54.571359	2025-08-03 20:01:54.571359	0.36	500.00
1641	\N	44	2025-02-03	6160.00	1	2025-08-03 20:01:54.813677	2025-08-03 20:01:54.813677	0.60	3696.00
1642	\N	44	2025-02-03	3550.00	1	2025-08-03 20:01:55.064553	2025-08-03 20:01:55.064553	0.60	2130.00
1643	\N	45	2025-02-03	3075.00	1	2025-08-03 20:01:55.318911	2025-08-03 20:01:55.318911	0.52	1600.00
1644	\N	105	2025-02-03	13257.00	1	2025-08-03 20:01:55.564624	2025-08-03 20:01:55.564624	0.65	8617.05
1645	\N	199	2025-02-03	6775.00	1	2025-08-03 20:01:56.005982	2025-08-03 20:01:56.005982	0.50	3387.50
1646	\N	123	2025-02-03	2555.00	1	2025-08-03 20:01:56.223385	2025-08-03 20:01:56.223385	0.67	1703.33
1647	\N	44	2025-02-04	12243.75	1	2025-08-03 20:01:56.477456	2025-08-03 20:01:56.477456	0.41	5076.21
1648	\N	44	2025-02-04	10375.19	1	2025-08-03 20:01:56.727852	2025-08-03 20:01:56.727852	0.45	4666.67
1649	\N	44	2025-02-04	10593.81	1	2025-08-03 20:01:57.046902	2025-08-03 20:01:57.046902	0.44	4666.67
1650	\N	80	2025-02-04	5575.00	1	2025-08-03 20:01:57.298154	2025-08-03 20:01:57.298154	0.54	3000.00
1651	\N	200	2025-02-04	10325.00	1	2025-08-03 20:01:57.730953	2025-08-03 20:01:57.730953	0.50	5200.00
1652	\N	48	2025-02-04	11210.00	1	2025-08-03 20:01:57.944661	2025-08-03 20:01:57.944661	0.54	6000.00
1653	\N	52	2025-02-04	2095.00	1	2025-08-03 20:01:58.232788	2025-08-03 20:01:58.232788	0.50	1047.50
1654	\N	52	2025-02-04	5350.33	1	2025-08-03 20:01:58.446954	2025-08-03 20:01:58.446954	0.50	2675.00
1655	\N	52	2025-02-04	4841.38	1	2025-08-03 20:01:58.652048	2025-08-03 20:01:58.652048	0.50	2422.00
1656	\N	52	2025-02-04	5305.80	1	2025-08-03 20:01:58.894526	2025-08-03 20:01:58.894526	0.50	2654.00
1657	\N	44	2025-02-05	12131.17	1	2025-08-03 20:01:59.145376	2025-08-03 20:01:59.145376	0.15	1805.67
1658	\N	44	2025-02-05	9613.96	1	2025-08-03 20:01:59.397486	2025-08-03 20:01:59.397486	0.76	7271.00
1659	\N	45	2025-02-05	5120.00	1	2025-08-03 20:01:59.651105	2025-08-03 20:01:59.651105	0.50	2560.00
1660	\N	127	2025-02-05	16728.70	1	2025-08-03 20:01:59.956346	2025-08-03 20:01:59.956346	0.65	10873.66
1661	\N	114	2025-02-05	8415.00	1	2025-08-03 20:02:00.218729	2025-08-03 20:02:00.218729	0.50	4200.00
1662	\N	124	2025-02-05	4210.00	1	2025-08-03 20:02:00.525585	2025-08-03 20:02:00.525585	0.42	1750.00
1663	\N	55	2025-02-05	5894.19	1	2025-08-03 20:02:00.764092	2025-08-03 20:02:00.764092	0.51	3000.00
1664	\N	44	2025-02-06	4036.66	1	2025-08-03 20:02:01.001912	2025-08-03 20:02:01.001912	0.52	2100.00
1665	\N	112	2025-02-06	9936.72	1	2025-08-03 20:02:01.336092	2025-08-03 20:02:01.336092	0.65	6458.85
1666	\N	135	2025-02-06	5245.00	1	2025-08-03 20:02:01.655158	2025-08-03 20:02:01.655158	0.51	2700.00
1667	\N	88	2025-02-06	9175.00	1	2025-08-03 20:02:01.891554	2025-08-03 20:02:01.891554	0.50	4600.00
1668	\N	201	2025-02-06	9015.75	1	2025-08-03 20:02:02.4092	2025-08-03 20:02:02.4092	0.60	5409.00
1669	\N	193	2025-02-06	4330.00	1	2025-08-03 20:02:02.629805	2025-08-03 20:02:02.629805	0.60	2598.00
1670	\N	86	2025-02-06	7962.05	1	2025-08-03 20:02:02.854569	2025-08-03 20:02:02.854569	0.50	3982.00
1671	\N	102	2025-02-06	1395.00	1	2025-08-03 20:02:03.091978	2025-08-03 20:02:03.091978	3.58	5000.00
1672	\N	84	2025-02-06	10820.00	1	2025-08-03 20:02:03.331624	2025-08-03 20:02:03.331624	0.39	4166.67
1673	\N	116	2025-02-06	7846.86	1	2025-08-03 20:02:03.594228	2025-08-03 20:02:03.594228	0.43	3374.12
1674	\N	57	2025-02-06	6575.00	1	2025-08-03 20:02:03.842595	2025-08-03 20:02:03.842595	0.27	1800.00
1675	\N	57	2025-02-06	11611.50	1	2025-08-03 20:02:04.089773	2025-08-03 20:02:04.089773	0.50	5748.21
1676	\N	57	2025-02-06	11036.78	1	2025-08-03 20:02:04.275783	2025-08-03 20:02:04.275783	0.47	5200.00
1677	\N	92	2025-02-07	2120.00	1	2025-08-03 20:02:04.527533	2025-08-03 20:02:04.527533	0.60	1272.00
1678	\N	194	2025-02-07	4380.00	1	2025-08-03 20:02:04.831183	2025-08-03 20:02:04.831183	0.50	2190.00
1679	\N	110	2025-02-07	1930.00	1	2025-08-03 20:02:05.080078	2025-08-03 20:02:05.080078	0.60	1158.00
1680	\N	116	2025-02-07	1530.00	1	2025-08-03 20:02:05.262755	2025-08-03 20:02:05.262755	0.55	841.50
1681	\N	57	2025-02-07	13045.00	1	2025-08-03 20:02:05.508599	2025-08-03 20:02:05.508599	0.59	7645.00
1682	\N	57	2025-02-07	10085.00	1	2025-08-03 20:02:05.755527	2025-08-03 20:02:05.755527	0.60	6051.00
1683	\N	57	2025-02-07	10188.95	1	2025-08-03 20:02:06.023306	2025-08-03 20:02:06.023306	0.57	5804.92
1684	\N	57	2025-02-07	6485.79	1	2025-08-03 20:02:06.28883	2025-08-03 20:02:06.28883	0.56	3600.00
1685	\N	57	2025-02-07	11185.00	1	2025-08-03 20:02:06.542179	2025-08-03 20:02:06.542179	0.60	6750.00
1686	\N	44	2025-02-10	7454.67	1	2025-08-03 20:02:06.812011	2025-08-03 20:02:06.812011	0.60	4454.66
1687	\N	66	2025-02-10	11035.00	1	2025-08-03 20:02:07.193741	2025-08-03 20:02:07.193741	0.50	5517.50
1688	\N	143	2025-02-10	8942.42	1	2025-08-03 20:02:07.394948	2025-08-03 20:02:07.394948	0.50	4471.21
1689	\N	57	2025-02-10	13325.17	1	2025-08-03 20:02:07.641974	2025-08-03 20:02:07.641974	0.20	2620.81
1690	\N	57	2025-02-10	7685.00	1	2025-08-03 20:02:07.907841	2025-08-03 20:02:07.907841	0.60	4611.00
1691	\N	57	2025-02-10	13838.69	1	2025-08-03 20:02:08.282915	2025-08-03 20:02:08.282915	0.60	8303.21
1692	\N	57	2025-02-10	13930.00	1	2025-08-03 20:02:08.525811	2025-08-03 20:02:08.525811	0.65	9100.00
1693	\N	57	2025-02-10	718.22	1	2025-08-03 20:02:08.766443	2025-08-03 20:02:08.766443	0.60	431.47
1694	\N	57	2025-02-10	14145.00	1	2025-08-03 20:02:09.009358	2025-08-03 20:02:09.009358	0.60	8487.00
1695	\N	57	2025-02-10	9690.00	1	2025-08-03 20:02:09.268859	2025-08-03 20:02:09.268859	0.68	6575.00
1696	\N	57	2025-02-10	11755.00	1	2025-08-03 20:02:09.474464	2025-08-03 20:02:09.474464	0.60	7030.00
1697	\N	43	2025-02-11	5265.00	1	2025-08-03 20:02:09.723553	2025-08-03 20:02:09.723553	0.50	2632.50
1698	\N	88	2025-02-11	12960.00	1	2025-08-03 20:02:09.975912	2025-08-03 20:02:09.975912	0.16	2073.60
1699	\N	103	2025-02-11	7807.24	1	2025-08-03 20:02:10.236792	2025-08-03 20:02:10.236792	0.65	5100.00
1700	\N	55	2025-02-11	11465.41	1	2025-08-03 20:02:10.435316	2025-08-03 20:02:10.435316	0.30	3465.41
1701	\N	102	2025-02-11	2120.47	1	2025-08-03 20:02:10.657092	2025-08-03 20:02:10.657092	0.60	1272.28
1702	\N	102	2025-02-11	10151.87	1	2025-08-03 20:02:10.889168	2025-08-03 20:02:10.889168	0.50	5075.94
1703	\N	102	2025-02-11	10250.04	1	2025-08-03 20:02:11.11042	2025-08-03 20:02:11.11042	0.50	5125.02
1704	\N	52	2025-02-11	11042.76	1	2025-08-03 20:02:11.467859	2025-08-03 20:02:11.467859	0.50	5521.76
1705	\N	57	2025-02-11	12419.58	1	2025-08-03 20:02:11.796626	2025-08-03 20:02:11.796626	0.60	7451.74
1706	\N	57	2025-02-11	2962.90	1	2025-08-03 20:02:11.998144	2025-08-03 20:02:11.998144	0.60	1777.74
1707	\N	57	2025-02-11	12418.28	1	2025-08-03 20:02:12.244801	2025-08-03 20:02:12.244801	0.60	7450.96
1708	\N	57	2025-02-11	11706.62	1	2025-08-03 20:02:12.487629	2025-08-03 20:02:12.487629	0.60	7023.96
1709	\N	57	2025-02-11	5810.00	1	2025-08-03 20:02:12.731636	2025-08-03 20:02:12.731636	0.60	3470.00
1710	\N	57	2025-02-11	17780.00	1	2025-08-03 20:02:13.104652	2025-08-03 20:02:13.104652	0.62	11100.00
1711	\N	57	2025-02-11	17780.00	1	2025-08-03 20:02:13.346464	2025-08-03 20:02:13.346464	0.62	11100.00
1712	\N	57	2025-02-11	9085.00	1	2025-08-03 20:02:13.59587	2025-08-03 20:02:13.59587	0.50	4542.50
1713	\N	57	2025-02-11	4605.00	1	2025-08-03 20:02:13.823459	2025-08-03 20:02:13.823459	0.62	2855.00
1714	\N	57	2025-02-11	10725.00	1	2025-08-03 20:02:14.081915	2025-08-03 20:02:14.081915	0.66	7125.00
1715	\N	57	2025-02-11	12425.00	1	2025-08-03 20:02:14.33923	2025-08-03 20:02:14.33923	0.58	7225.00
1716	\N	57	2025-02-11	10637.96	1	2025-08-03 20:02:14.590272	2025-08-03 20:02:14.590272	0.71	7537.96
1717	\N	57	2025-02-11	8360.00	1	2025-08-03 20:02:14.781288	2025-08-03 20:02:14.781288	0.60	5016.00
1718	\N	57	2025-02-11	4532.50	1	2025-08-03 20:02:14.962675	2025-08-03 20:02:14.962675	0.60	2719.50
1719	\N	57	2025-02-11	13262.10	1	2025-08-03 20:02:15.21121	2025-08-03 20:02:15.21121	0.50	6653.00
1720	\N	57	2025-02-11	6473.67	1	2025-08-03 20:02:15.554062	2025-08-03 20:02:15.554062	0.65	4207.88
1721	\N	57	2025-02-11	2340.00	1	2025-08-03 20:02:15.805939	2025-08-03 20:02:15.805939	0.59	1390.00
1722	\N	57	2025-02-11	2205.00	1	2025-08-03 20:02:16.052671	2025-08-03 20:02:16.052671	0.64	1405.00
1723	\N	57	2025-02-11	11795.00	1	2025-08-03 20:02:16.28519	2025-08-03 20:02:16.28519	0.55	6472.25
1724	\N	57	2025-02-11	11048.61	1	2025-08-03 20:02:16.531894	2025-08-03 20:02:16.531894	0.60	6629.16
1725	\N	57	2025-02-11	6720.00	1	2025-08-03 20:02:16.766116	2025-08-03 20:02:16.766116	0.60	4032.00
1726	\N	57	2025-02-11	16875.00	1	2025-08-03 20:02:16.946915	2025-08-03 20:02:16.946915	0.60	10125.00
1727	\N	57	2025-02-11	10875.00	1	2025-08-03 20:02:17.201944	2025-08-03 20:02:17.201944	0.64	6925.00
1728	\N	57	2025-02-11	11937.61	1	2025-08-03 20:02:17.435276	2025-08-03 20:02:17.435276	0.60	7162.56
1729	\N	57	2025-02-11	707.90	1	2025-08-03 20:02:17.680614	2025-08-03 20:02:17.680614	0.58	407.90
1730	\N	57	2025-02-11	7781.25	1	2025-08-03 20:02:18.037966	2025-08-03 20:02:18.037966	0.66	5126.25
1731	\N	57	2025-02-11	9565.17	1	2025-08-03 20:02:18.286993	2025-08-03 20:02:18.286993	0.60	5739.10
1732	\N	57	2025-02-11	5910.79	1	2025-08-03 20:02:18.537632	2025-08-03 20:02:18.537632	0.52	3080.00
1733	\N	57	2025-02-11	9330.00	1	2025-08-03 20:02:18.777326	2025-08-03 20:02:18.777326	0.52	4830.00
1734	\N	57	2025-02-11	6126.70	1	2025-08-03 20:02:19.022337	2025-08-03 20:02:19.022337	0.60	3674.22
1735	\N	53	2025-02-11	6695.00	1	2025-08-03 20:02:19.276168	2025-08-03 20:02:19.276168	0.51	3400.00
1736	\N	45	2025-02-12	15962.75	1	2025-08-03 20:02:19.542285	2025-08-03 20:02:19.542285	0.50	7981.38
1737	\N	84	2025-02-12	9202.12	1	2025-08-03 20:02:19.831955	2025-08-03 20:02:19.831955	0.76	6950.00
1738	\N	116	2025-02-12	2619.76	1	2025-08-03 20:02:20.024053	2025-08-03 20:02:20.024053	0.00	0.00
1739	\N	57	2025-02-12	8570.00	1	2025-08-03 20:02:20.216179	2025-08-03 20:02:20.216179	0.59	5052.00
1740	\N	57	2025-02-12	9715.50	1	2025-08-03 20:02:20.458507	2025-08-03 20:02:20.458507	0.60	5829.30
1741	\N	57	2025-02-12	7498.74	1	2025-08-03 20:02:20.819529	2025-08-03 20:02:20.819529	0.52	3871.47
1742	\N	57	2025-02-12	11950.95	1	2025-08-03 20:02:21.077229	2025-08-03 20:02:21.077229	0.50	5975.47
1743	\N	57	2025-02-12	12215.00	1	2025-08-03 20:02:21.340018	2025-08-03 20:02:21.340018	0.50	6107.50
1744	\N	53	2025-02-12	8040.00	1	2025-08-03 20:02:21.567267	2025-08-03 20:02:21.567267	0.51	4100.00
1745	\N	53	2025-02-12	7860.00	1	2025-08-03 20:02:21.815013	2025-08-03 20:02:21.815013	0.51	4000.00
1746	\N	53	2025-02-12	10025.00	1	2025-08-03 20:02:22.055123	2025-08-03 20:02:22.055123	0.51	5100.00
1747	\N	44	2025-02-13	11725.17	1	2025-08-03 20:02:22.303567	2025-08-03 20:02:22.303567	0.31	3674.58
1748	\N	44	2025-02-13	13416.46	1	2025-08-03 20:02:22.551106	2025-08-03 20:02:22.551106	0.53	7108.32
1749	\N	44	2025-02-13	8680.00	1	2025-08-03 20:02:22.79799	2025-08-03 20:02:22.79799	0.70	6076.00
1750	\N	44	2025-02-13	10996.39	1	2025-08-03 20:02:22.994465	2025-08-03 20:02:22.994465	0.65	7149.50
1751	\N	44	2025-02-13	4945.00	1	2025-08-03 20:02:23.244162	2025-08-03 20:02:23.244162	0.39	1923.19
1752	\N	44	2025-02-13	7535.00	1	2025-08-03 20:02:23.495458	2025-08-03 20:02:23.495458	0.67	5035.00
1753	\N	44	2025-02-13	9912.35	1	2025-08-03 20:02:23.7341	2025-08-03 20:02:23.7341	0.61	6053.00
1754	\N	80	2025-02-13	8270.00	1	2025-08-03 20:02:23.988248	2025-08-03 20:02:23.988248	0.60	4962.00
1755	\N	52	2025-02-13	2693.69	1	2025-08-03 20:02:24.240068	2025-08-03 20:02:24.240068	0.50	1348.00
1756	\N	57	2025-02-13	7266.05	1	2025-08-03 20:02:24.48647	2025-08-03 20:02:24.48647	0.58	4240.00
1757	\N	57	2025-02-13	13815.73	1	2025-08-03 20:02:24.684413	2025-08-03 20:02:24.684413	0.55	7598.65
1758	\N	57	2025-02-13	8495.69	1	2025-08-03 20:02:24.909279	2025-08-03 20:02:24.909279	0.60	5097.00
1759	\N	57	2025-02-13	11058.98	1	2025-08-03 20:02:25.251134	2025-08-03 20:02:25.251134	0.59	6473.27
1760	\N	57	2025-02-13	13023.66	1	2025-08-03 20:02:25.480099	2025-08-03 20:02:25.480099	0.65	8464.78
1761	\N	57	2025-02-13	9062.62	1	2025-08-03 20:02:25.674282	2025-08-03 20:02:25.674282	0.67	6061.80
1762	\N	57	2025-02-13	4280.00	1	2025-08-03 20:02:25.914567	2025-08-03 20:02:25.914567	0.58	2480.00
1763	\N	57	2025-02-13	16897.08	1	2025-08-03 20:02:26.169052	2025-08-03 20:02:26.169052	0.58	9880.00
1764	\N	57	2025-02-13	13700.00	1	2025-08-03 20:02:26.529904	2025-08-03 20:02:26.529904	0.65	8905.00
1765	\N	57	2025-02-13	9635.00	1	2025-08-03 20:02:26.791219	2025-08-03 20:02:26.791219	0.57	5499.25
1766	\N	57	2025-02-13	12155.00	1	2025-08-03 20:02:26.997543	2025-08-03 20:02:26.997543	0.55	6685.25
1767	\N	57	2025-02-13	3350.00	1	2025-08-03 20:02:27.180099	2025-08-03 20:02:27.180099	0.55	1850.00
1768	\N	57	2025-02-13	7545.00	1	2025-08-03 20:02:27.412408	2025-08-03 20:02:27.412408	0.60	4527.00
1769	\N	57	2025-02-13	10155.00	1	2025-08-03 20:02:27.655224	2025-08-03 20:02:27.655224	0.58	5900.00
1770	\N	57	2025-02-13	10385.00	1	2025-08-03 20:02:27.903051	2025-08-03 20:02:27.903051	0.60	6240.00
1771	\N	57	2025-02-13	8810.00	1	2025-08-03 20:02:28.147099	2025-08-03 20:02:28.147099	0.54	4764.75
1772	\N	57	2025-02-13	8810.00	1	2025-08-03 20:02:28.367753	2025-08-03 20:02:28.367753	0.54	4764.75
1773	\N	57	2025-02-13	7435.00	1	2025-08-03 20:02:28.612546	2025-08-03 20:02:28.612546	0.60	4461.00
1774	\N	57	2025-02-13	5659.30	1	2025-08-03 20:02:28.955102	2025-08-03 20:02:28.955102	0.60	3395.58
1775	\N	57	2025-02-13	3928.97	1	2025-08-03 20:02:29.231063	2025-08-03 20:02:29.231063	0.67	2648.97
1776	\N	57	2025-02-13	4670.00	1	2025-08-03 20:02:29.577829	2025-08-03 20:02:29.577829	0.60	2802.00
1777	\N	57	2025-02-13	5744.87	1	2025-08-03 20:02:29.770211	2025-08-03 20:02:29.770211	0.60	3446.92
1778	\N	53	2025-02-13	6885.00	1	2025-08-03 20:02:30.025684	2025-08-03 20:02:30.025684	0.60	4100.00
1779	\N	44	2025-02-14	1759.30	1	2025-08-03 20:02:30.29187	2025-08-03 20:02:30.29187	0.76	1333.33
1780	\N	44	2025-02-14	8102.90	1	2025-08-03 20:02:30.670764	2025-08-03 20:02:30.670764	0.47	3802.05
1781	\N	44	2025-02-14	2810.00	1	2025-08-03 20:02:31.028416	2025-08-03 20:02:31.028416	0.68	1904.00
1782	\N	44	2025-02-14	7165.00	1	2025-08-03 20:02:31.218506	2025-08-03 20:02:31.218506	0.64	4580.80
1783	\N	44	2025-02-14	4252.28	1	2025-08-03 20:02:31.543727	2025-08-03 20:02:31.543727	0.42	1777.93
1784	\N	44	2025-02-14	8984.59	1	2025-08-03 20:02:31.800111	2025-08-03 20:02:31.800111	0.50	4514.65
1785	\N	44	2025-02-14	12533.28	1	2025-08-03 20:02:32.047886	2025-08-03 20:02:32.047886	0.56	7062.00
1786	\N	44	2025-02-14	3460.66	1	2025-08-03 20:02:32.299786	2025-08-03 20:02:32.299786	0.49	1679.32
1787	\N	44	2025-02-14	2470.00	1	2025-08-03 20:02:32.497298	2025-08-03 20:02:32.497298	0.70	1729.00
1788	\N	57	2025-02-14	18187.61	1	2025-08-03 20:02:32.747678	2025-08-03 20:02:32.747678	0.55	10003.18
1789	\N	57	2025-02-14	7038.48	1	2025-08-03 20:02:33.005638	2025-08-03 20:02:33.005638	0.57	4000.00
1790	\N	57	2025-02-14	8672.21	1	2025-08-03 20:02:33.251358	2025-08-03 20:02:33.251358	0.56	4880.00
1791	\N	57	2025-02-14	10924.29	1	2025-08-03 20:02:33.610685	2025-08-03 20:02:33.610685	0.60	6511.37
1792	\N	57	2025-02-14	4698.88	1	2025-08-03 20:02:33.959872	2025-08-03 20:02:33.959872	0.51	2400.00
1793	\N	57	2025-02-14	11036.00	1	2025-08-03 20:02:34.220196	2025-08-03 20:02:34.220196	0.50	5520.00
1794	\N	57	2025-02-14	11036.78	1	2025-08-03 20:02:34.474119	2025-08-03 20:02:34.474119	0.50	5520.00
1795	\N	57	2025-02-14	11611.50	1	2025-08-03 20:02:34.73751	2025-08-03 20:02:34.73751	0.50	5748.21
1796	\N	57	2025-02-14	5500.00	1	2025-08-03 20:02:34.929683	2025-08-03 20:02:34.929683	0.55	3025.00
1797	\N	57	2025-02-14	10580.00	1	2025-08-03 20:02:35.167867	2025-08-03 20:02:35.167867	0.60	6348.00
1798	\N	57	2025-02-14	8681.45	1	2025-08-03 20:02:35.42947	2025-08-03 20:02:35.42947	0.57	4974.88
1799	\N	57	2025-02-14	12745.00	1	2025-08-03 20:02:35.66798	2025-08-03 20:02:35.66798	0.60	7647.00
1800	\N	57	2025-02-14	890.00	1	2025-08-03 20:02:36.030783	2025-08-03 20:02:36.030783	0.40	356.00
1801	\N	57	2025-02-14	10155.18	1	2025-08-03 20:02:36.235101	2025-08-03 20:02:36.235101	0.60	6050.00
1802	\N	57	2025-02-14	7720.00	1	2025-08-03 20:02:36.471221	2025-08-03 20:02:36.471221	0.52	4000.00
1803	\N	44	2025-02-18	9977.59	1	2025-08-03 20:02:36.721057	2025-08-03 20:02:36.721057	0.55	5465.61
1804	\N	44	2025-02-18	12086.40	1	2025-08-03 20:02:37.081315	2025-08-03 20:02:37.081315	0.25	3042.79
1805	\N	44	2025-02-18	12757.63	1	2025-08-03 20:02:37.33149	2025-08-03 20:02:37.33149	0.34	4366.66
1806	\N	44	2025-02-18	2272.11	1	2025-08-03 20:02:37.587117	2025-08-03 20:02:37.587117	0.75	1706.00
1807	\N	44	2025-02-18	4313.98	1	2025-08-03 20:02:37.960343	2025-08-03 20:02:37.960343	0.70	3019.79
1808	\N	44	2025-02-18	9689.42	1	2025-08-03 20:02:38.225955	2025-08-03 20:02:38.225955	0.23	2246.66
1809	\N	137	2025-02-18	6965.00	1	2025-08-03 20:02:38.462851	2025-08-03 20:02:38.462851	0.30	2089.50
1810	\N	167	2025-02-18	4075.00	1	2025-08-03 20:02:38.71225	2025-08-03 20:02:38.71225	0.50	2035.50
1811	\N	167	2025-02-18	4040.00	1	2025-08-03 20:02:38.953811	2025-08-03 20:02:38.953811	0.50	2020.00
1812	\N	55	2025-02-18	823.10	1	2025-08-03 20:02:39.204851	2025-08-03 20:02:39.204851	0.67	550.00
1813	\N	55	2025-02-18	1280.00	1	2025-08-03 20:02:39.443171	2025-08-03 20:02:39.443171	0.77	984.87
1814	\N	84	2025-02-18	9515.00	1	2025-08-03 20:02:39.698158	2025-08-03 20:02:39.698158	0.61	5800.00
1815	\N	84	2025-02-18	3795.00	1	2025-08-03 20:02:39.943412	2025-08-03 20:02:39.943412	0.42	1600.00
1816	\N	84	2025-02-18	8209.27	1	2025-08-03 20:02:40.198966	2025-08-03 20:02:40.198966	0.32	2648.57
1817	\N	57	2025-02-18	16815.00	1	2025-08-03 20:02:40.44688	2025-08-03 20:02:40.44688	0.58	9800.00
1818	\N	57	2025-02-18	6505.00	1	2025-08-03 20:02:40.649379	2025-08-03 20:02:40.649379	0.60	3900.00
1819	\N	57	2025-02-18	5062.54	1	2025-08-03 20:02:40.887649	2025-08-03 20:02:40.887649	0.55	2784.48
1820	\N	57	2025-02-18	8585.00	1	2025-08-03 20:02:41.176601	2025-08-03 20:02:41.176601	0.60	5120.00
1821	\N	57	2025-02-18	13335.05	1	2025-08-03 20:02:41.395448	2025-08-03 20:02:41.395448	0.60	8001.03
1822	\N	57	2025-02-18	12125.00	1	2025-08-03 20:02:41.676138	2025-08-03 20:02:41.676138	0.52	6300.00
1823	\N	57	2025-02-18	3940.00	1	2025-08-03 20:02:41.929394	2025-08-03 20:02:41.929394	0.55	2167.00
1824	\N	57	2025-02-18	13250.00	1	2025-08-03 20:02:42.13209	2025-08-03 20:02:42.13209	0.70	9275.00
1825	\N	57	2025-02-18	10040.00	1	2025-08-03 20:02:42.373745	2025-08-03 20:02:42.373745	0.56	5600.00
1826	\N	57	2025-02-18	10407.16	1	2025-08-03 20:02:42.63164	2025-08-03 20:02:42.63164	0.51	5307.16
1827	\N	44	2025-02-19	7070.18	1	2025-08-03 20:02:42.882483	2025-08-03 20:02:42.882483	0.54	3836.89
1828	\N	44	2025-02-19	12798.72	1	2025-08-03 20:02:43.19171	2025-08-03 20:02:43.19171	0.46	5877.38
1829	\N	44	2025-02-19	6080.00	1	2025-08-03 20:02:43.382486	2025-08-03 20:02:43.382486	0.67	4066.29
1830	\N	202	2025-02-19	21240.22	1	2025-08-03 20:02:43.841926	2025-08-03 20:02:43.841926	0.60	12744.13
1831	\N	83	2025-02-19	6930.00	1	2025-08-03 20:02:44.062924	2025-08-03 20:02:44.062924	0.50	3465.00
1832	\N	124	2025-02-19	7140.00	1	2025-08-03 20:02:44.311663	2025-08-03 20:02:44.311663	0.65	4641.00
1833	\N	124	2025-02-19	5930.00	1	2025-08-03 20:02:44.579696	2025-08-03 20:02:44.579696	0.50	2965.00
1834	\N	102	2025-02-19	6920.00	1	2025-08-03 20:02:44.906559	2025-08-03 20:02:44.906559	0.50	3460.00
1835	\N	108	2025-02-19	7694.97	1	2025-08-03 20:02:45.166262	2025-08-03 20:02:45.166262	0.40	3077.99
1836	\N	203	2025-02-19	6480.00	1	2025-08-03 20:02:45.713159	2025-08-03 20:02:45.713159	0.46	3000.00
1837	\N	57	2025-02-19	3545.94	1	2025-08-03 20:02:45.962655	2025-08-03 20:02:45.962655	0.35	1241.06
1838	\N	57	2025-02-19	7785.00	1	2025-08-03 20:02:46.176227	2025-08-03 20:02:46.176227	0.50	3885.00
1839	\N	57	2025-02-19	7785.00	1	2025-08-03 20:02:46.433861	2025-08-03 20:02:46.433861	0.50	3885.00
1840	\N	57	2025-02-19	2390.00	1	2025-08-03 20:02:46.63994	2025-08-03 20:02:46.63994	0.40	956.00
1841	\N	57	2025-02-19	11715.00	1	2025-08-03 20:02:46.884899	2025-08-03 20:02:46.884899	0.40	4686.00
1842	\N	57	2025-02-19	8240.00	1	2025-08-03 20:02:47.133985	2025-08-03 20:02:47.133985	0.55	4532.00
1843	\N	57	2025-02-19	2803.18	1	2025-08-03 20:02:47.381976	2025-08-03 20:02:47.381976	0.54	1500.00
1844	\N	57	2025-02-19	5710.00	1	2025-08-03 20:02:47.638371	2025-08-03 20:02:47.638371	0.60	3426.00
1845	\N	57	2025-02-19	7980.00	1	2025-08-03 20:02:47.888454	2025-08-03 20:02:47.888454	0.61	4900.00
1846	\N	57	2025-02-19	12051.01	1	2025-08-03 20:02:48.140335	2025-08-03 20:02:48.140335	0.50	5975.00
1847	\N	44	2025-02-20	615.25	1	2025-08-03 20:02:48.387355	2025-08-03 20:02:48.387355	0.60	371.67
1848	\N	44	2025-02-20	11515.67	1	2025-08-03 20:02:48.64374	2025-08-03 20:02:48.64374	0.36	4171.89
1849	\N	44	2025-02-20	5675.59	1	2025-08-03 20:02:48.851218	2025-08-03 20:02:48.851218	0.52	2944.53
1850	\N	44	2025-02-20	7200.00	1	2025-08-03 20:02:49.102565	2025-08-03 20:02:49.102565	0.49	3550.50
1851	\N	71	2025-02-20	3862.85	1	2025-08-03 20:02:49.356448	2025-08-03 20:02:49.356448	0.35	1352.00
1852	\N	71	2025-02-20	7718.59	1	2025-08-03 20:02:49.632539	2025-08-03 20:02:49.632539	0.40	3087.40
1853	\N	71	2025-02-20	10580.14	1	2025-08-03 20:02:50.016371	2025-08-03 20:02:50.016371	0.40	4232.00
1854	\N	88	2025-02-20	10590.00	1	2025-08-03 20:02:50.237211	2025-08-03 20:02:50.237211	0.52	5506.80
1855	\N	88	2025-02-20	7130.00	1	2025-08-03 20:02:50.495909	2025-08-03 20:02:50.495909	0.50	3565.00
1856	\N	88	2025-02-20	14811.75	1	2025-08-03 20:02:50.74962	2025-08-03 20:02:50.74962	0.90	13330.75
1857	\N	88	2025-02-20	6250.00	1	2025-08-03 20:02:51.000329	2025-08-03 20:02:51.000329	0.50	3125.00
1858	\N	88	2025-02-20	10370.00	1	2025-08-03 20:02:51.234985	2025-08-03 20:02:51.234985	0.48	5000.00
1859	\N	102	2025-02-20	6445.00	1	2025-08-03 20:02:51.48335	2025-08-03 20:02:51.48335	0.60	3867.00
1860	\N	84	2025-02-20	6958.56	1	2025-08-03 20:02:51.743384	2025-08-03 20:02:51.743384	0.78	5450.00
1861	\N	57	2025-02-20	14582.58	1	2025-08-03 20:02:51.998047	2025-08-03 20:02:51.998047	0.50	7291.28
1862	\N	57	2025-02-20	9796.11	1	2025-08-03 20:02:52.265495	2025-08-03 20:02:52.265495	0.60	5877.66
1863	\N	57	2025-02-20	5530.00	1	2025-08-03 20:02:52.525897	2025-08-03 20:02:52.525897	0.33	1845.64
1864	\N	57	2025-02-20	9910.00	1	2025-08-03 20:02:52.898016	2025-08-03 20:02:52.898016	0.60	5946.00
1865	\N	57	2025-02-20	8622.74	1	2025-08-03 20:02:53.150601	2025-08-03 20:02:53.150601	0.34	2900.00
1866	\N	53	2025-02-20	1445.00	1	2025-08-03 20:02:53.405188	2025-08-03 20:02:53.405188	0.50	722.50
1867	\N	53	2025-02-20	4800.00	1	2025-08-03 20:02:53.75323	2025-08-03 20:02:53.75323	0.50	2400.00
1868	\N	44	2025-02-21	3475.00	1	2025-08-03 20:02:53.989353	2025-08-03 20:02:53.989353	0.57	1976.00
1869	\N	44	2025-02-21	7070.18	1	2025-08-03 20:02:54.249167	2025-08-03 20:02:54.249167	0.54	3836.89
1870	\N	44	2025-02-21	1285.00	1	2025-08-03 20:02:54.509648	2025-08-03 20:02:54.509648	0.70	899.50
1871	\N	44	2025-02-21	8370.10	1	2025-08-03 20:02:54.756514	2025-08-03 20:02:54.756514	0.70	5859.07
1872	\N	44	2025-02-21	2947.23	1	2025-08-03 20:02:55.015082	2025-08-03 20:02:55.015082	0.70	2063.06
1873	\N	44	2025-02-21	11415.22	1	2025-08-03 20:02:55.265405	2025-08-03 20:02:55.265405	0.22	2562.08
1874	\N	44	2025-02-21	10395.00	1	2025-08-03 20:02:55.521106	2025-08-03 20:02:55.521106	0.70	7276.50
1875	\N	94	2025-02-21	5255.00	1	2025-08-03 20:02:55.743885	2025-08-03 20:02:55.743885	0.50	2627.50
1876	\N	80	2025-02-21	5195.00	1	2025-08-03 20:02:56.003732	2025-08-03 20:02:56.003732	0.30	1558.50
1877	\N	57	2025-02-21	12030.00	1	2025-08-03 20:02:56.332542	2025-08-03 20:02:56.332542	0.50	6015.00
1878	\N	57	2025-02-21	6055.00	1	2025-08-03 20:02:56.59112	2025-08-03 20:02:56.59112	0.50	3027.50
1879	\N	57	2025-02-21	7700.00	1	2025-08-03 20:02:56.840217	2025-08-03 20:02:56.840217	0.69	5350.00
1880	\N	57	2025-02-21	12011.30	1	2025-08-03 20:02:57.037911	2025-08-03 20:02:57.037911	0.51	6111.30
1881	\N	57	2025-02-21	11939.52	1	2025-08-03 20:02:57.291867	2025-08-03 20:02:57.291867	0.54	6500.00
1882	\N	57	2025-02-21	9060.00	1	2025-08-03 20:02:57.56408	2025-08-03 20:02:57.56408	0.60	5450.00
1883	\N	57	2025-02-21	500.00	1	2025-08-03 20:02:57.81663	2025-08-03 20:02:57.81663	0.33	166.67
1884	\N	57	2025-02-21	2635.00	1	2025-08-03 20:02:58.085857	2025-08-03 20:02:58.085857	0.50	1320.00
1885	\N	57	2025-02-21	550.00	1	2025-08-03 20:02:58.366963	2025-08-03 20:02:58.366963	0.70	385.00
1886	\N	57	2025-02-21	7815.00	1	2025-08-03 20:02:58.634508	2025-08-03 20:02:58.634508	0.61	4754.00
1887	\N	57	2025-02-21	5170.00	1	2025-08-03 20:02:59.033293	2025-08-03 20:02:59.033293	0.53	2758.00
1888	\N	57	2025-02-21	5514.22	1	2025-08-03 20:02:59.285636	2025-08-03 20:02:59.285636	0.60	3308.00
1889	\N	57	2025-02-21	7360.00	1	2025-08-03 20:02:59.529887	2025-08-03 20:02:59.529887	0.16	1180.00
1890	\N	44	2025-02-24	9173.15	1	2025-08-03 20:02:59.73713	2025-08-03 20:02:59.73713	0.50	4586.57
1891	\N	44	2025-02-24	3425.00	1	2025-08-03 20:03:00.083928	2025-08-03 20:03:00.083928	0.36	1238.66
1892	\N	44	2025-02-24	9375.00	1	2025-08-03 20:03:00.340443	2025-08-03 20:03:00.340443	0.46	4313.40
1893	\N	44	2025-02-24	9068.55	1	2025-08-03 20:03:00.587874	2025-08-03 20:03:00.587874	0.42	3837.42
1894	\N	135	2025-02-24	10070.00	1	2025-08-03 20:03:00.825804	2025-08-03 20:03:00.825804	0.70	7049.00
1895	\N	88	2025-02-24	2515.00	1	2025-08-03 20:03:01.058351	2025-08-03 20:03:01.058351	0.50	1257.50
1896	\N	88	2025-02-24	16674.55	1	2025-08-03 20:03:01.24453	2025-08-03 20:03:01.24453	0.48	8000.00
1897	\N	88	2025-02-24	11915.00	1	2025-08-03 20:03:01.477375	2025-08-03 20:03:01.477375	0.53	6319.88
1898	\N	48	2025-02-24	8391.57	1	2025-08-03 20:03:01.720387	2025-08-03 20:03:01.720387	0.60	5034.94
1899	\N	57	2025-02-24	6635.00	1	2025-08-03 20:03:01.959448	2025-08-03 20:03:01.959448	0.60	3981.00
1900	\N	57	2025-02-24	7985.00	1	2025-08-03 20:03:02.193173	2025-08-03 20:03:02.193173	0.60	4791.00
1901	\N	57	2025-02-24	5445.00	1	2025-08-03 20:03:02.43375	2025-08-03 20:03:02.43375	0.60	3267.00
1902	\N	57	2025-02-24	6780.00	1	2025-08-03 20:03:02.667055	2025-08-03 20:03:02.667055	0.13	890.00
1903	\N	57	2025-02-24	10130.00	1	2025-08-03 20:03:03.010584	2025-08-03 20:03:03.010584	0.45	4558.50
1904	\N	53	2025-02-24	7395.00	1	2025-08-03 20:03:03.205741	2025-08-03 20:03:03.205741	0.41	3000.00
1905	\N	44	2025-02-25	12201.99	1	2025-08-03 20:03:03.431111	2025-08-03 20:03:03.431111	0.51	6278.22
1906	\N	44	2025-02-25	6300.00	1	2025-08-03 20:03:03.666053	2025-08-03 20:03:03.666053	0.33	2100.00
1907	\N	44	2025-02-25	3381.40	1	2025-08-03 20:03:03.876483	2025-08-03 20:03:03.876483	0.49	1640.86
1908	\N	44	2025-02-25	7764.36	1	2025-08-03 20:03:04.235659	2025-08-03 20:03:04.235659	0.35	2738.66
1909	\N	45	2025-02-25	5080.00	1	2025-08-03 20:03:04.501385	2025-08-03 20:03:04.501385	0.49	2475.00
1910	\N	137	2025-02-25	5950.00	1	2025-08-03 20:03:04.775119	2025-08-03 20:03:04.775119	0.30	1785.00
1911	\N	71	2025-02-25	5310.00	1	2025-08-03 20:03:05.045205	2025-08-03 20:03:05.045205	0.42	2250.00
1912	\N	204	2025-02-25	10075.00	1	2025-08-03 20:03:05.448586	2025-08-03 20:03:05.448586	0.50	5037.50
1913	\N	135	2025-02-25	11410.00	1	2025-08-03 20:03:05.673455	2025-08-03 20:03:05.673455	0.26	3000.00
1914	\N	88	2025-02-25	550.00	1	2025-08-03 20:03:05.918158	2025-08-03 20:03:05.918158	0.51	280.00
1915	\N	152	2025-02-25	5660.00	1	2025-08-03 20:03:06.183797	2025-08-03 20:03:06.183797	0.20	1132.00
1916	\N	184	2025-02-25	11395.00	1	2025-08-03 20:03:06.456269	2025-08-03 20:03:06.456269	0.40	4558.00
1917	\N	120	2025-02-25	7759.96	1	2025-08-03 20:03:06.718572	2025-08-03 20:03:06.718572	0.55	4267.98
1918	\N	80	2025-02-25	6415.00	1	2025-08-03 20:03:06.934072	2025-08-03 20:03:06.934072	0.55	3500.00
1919	\N	65	2025-02-25	11076.39	1	2025-08-03 20:03:07.178786	2025-08-03 20:03:07.178786	0.40	4430.56
1920	\N	48	2025-02-25	10185.00	1	2025-08-03 20:03:07.529688	2025-08-03 20:03:07.529688	0.40	4074.00
1921	\N	55	2025-02-25	8765.73	1	2025-08-03 20:03:07.790352	2025-08-03 20:03:07.790352	0.44	3813.60
1922	\N	55	2025-02-25	5375.00	1	2025-08-03 20:03:08.096606	2025-08-03 20:03:08.096606	0.56	3000.00
1923	\N	55	2025-02-25	6310.00	1	2025-08-03 20:03:08.341781	2025-08-03 20:03:08.341781	0.40	2551.60
1924	\N	84	2025-02-25	6155.75	1	2025-08-03 20:03:08.601569	2025-08-03 20:03:08.601569	0.44	2688.01
1925	\N	126	2025-02-25	1470.00	1	2025-08-03 20:03:08.951163	2025-08-03 20:03:08.951163	0.68	1000.00
1926	\N	57	2025-02-25	905.00	1	2025-08-03 20:03:09.206446	2025-08-03 20:03:09.206446	0.51	460.00
1927	\N	57	2025-02-25	4625.00	1	2025-08-03 20:03:09.463292	2025-08-03 20:03:09.463292	0.60	2775.00
1928	\N	57	2025-02-25	9485.00	1	2025-08-03 20:03:09.726984	2025-08-03 20:03:09.726984	0.60	5691.00
1929	\N	57	2025-02-25	550.00	1	2025-08-03 20:03:09.986803	2025-08-03 20:03:09.986803	0.35	192.50
1930	\N	53	2025-02-25	9980.00	1	2025-08-03 20:03:10.239513	2025-08-03 20:03:10.239513	0.50	5000.00
1931	\N	44	2025-02-26	4101.00	1	2025-08-03 20:03:10.501835	2025-08-03 20:03:10.501835	0.50	2050.50
1932	\N	44	2025-02-26	4101.00	1	2025-08-03 20:03:10.707877	2025-08-03 20:03:10.707877	0.60	2460.00
1933	\N	44	2025-02-26	12710.70	1	2025-08-03 20:03:11.026162	2025-08-03 20:03:11.026162	0.70	8897.49
1934	\N	44	2025-02-26	700.00	1	2025-08-03 20:03:11.281445	2025-08-03 20:03:11.281445	0.70	490.00
1935	\N	120	2025-02-26	8057.00	1	2025-08-03 20:03:11.529215	2025-08-03 20:03:11.529215	0.55	4431.35
1936	\N	52	2025-02-26	9181.23	1	2025-08-03 20:03:11.785052	2025-08-03 20:03:11.785052	0.50	4592.00
1937	\N	52	2025-02-26	8460.07	1	2025-08-03 20:03:12.01794	2025-08-03 20:03:12.01794	0.50	4230.00
1938	\N	57	2025-02-26	550.00	1	2025-08-03 20:03:12.278521	2025-08-03 20:03:12.278521	0.18	100.00
1939	\N	116	2025-02-26	1975.00	1	2025-08-03 20:03:12.532131	2025-08-03 20:03:12.532131	0.55	1086.25
1940	\N	57	2025-02-26	9757.23	1	2025-08-03 20:03:12.787224	2025-08-03 20:03:12.787224	0.40	3902.89
1941	\N	57	2025-02-26	8360.00	1	2025-08-03 20:03:13.042476	2025-08-03 20:03:13.042476	0.58	4827.50
1942	\N	57	2025-02-26	12635.00	1	2025-08-03 20:03:13.304191	2025-08-03 20:03:13.304191	0.50	6350.00
1943	\N	57	2025-02-26	6915.00	1	2025-08-03 20:03:13.598844	2025-08-03 20:03:13.598844	0.57	3967.00
1944	\N	57	2025-02-26	12440.00	1	2025-08-03 20:03:13.866192	2025-08-03 20:03:13.866192	0.10	1225.00
1945	\N	57	2025-02-26	8254.35	1	2025-08-03 20:03:14.132743	2025-08-03 20:03:14.132743	0.56	4608.89
1946	\N	57	2025-02-26	16465.00	1	2025-08-03 20:03:14.376367	2025-08-03 20:03:14.376367	0.50	8275.00
1947	\N	60	2025-02-26	9704.92	1	2025-08-03 20:03:14.639844	2025-08-03 20:03:14.639844	0.60	5822.95
1948	\N	53	2025-02-26	5943.28	1	2025-08-03 20:03:14.995623	2025-08-03 20:03:14.995623	0.71	4200.00
1949	\N	44	2025-02-27	700.00	1	2025-08-03 20:03:15.254449	2025-08-03 20:03:15.254449	0.60	420.00
1950	\N	205	2025-02-27	8510.56	1	2025-08-03 20:03:15.690221	2025-08-03 20:03:15.690221	0.53	4500.00
1951	\N	110	2025-02-27	5945.00	1	2025-08-03 20:03:15.956464	2025-08-03 20:03:15.956464	0.55	3269.75
1952	\N	57	2025-02-27	10360.00	1	2025-08-03 20:03:16.172358	2025-08-03 20:03:16.172358	0.60	6216.00
1953	\N	57	2025-02-27	8446.92	1	2025-08-03 20:03:16.623832	2025-08-03 20:03:16.623832	0.62	5210.00
1954	\N	57	2025-02-27	12288.62	1	2025-08-03 20:03:16.961384	2025-08-03 20:03:16.961384	0.56	6900.00
1955	\N	57	2025-02-27	9265.00	1	2025-08-03 20:03:17.22399	2025-08-03 20:03:17.22399	0.51	4700.00
1956	\N	57	2025-02-27	7125.09	1	2025-08-03 20:03:17.472873	2025-08-03 20:03:17.472873	0.68	4810.00
1957	\N	57	2025-02-27	14125.00	1	2025-08-03 20:03:17.734852	2025-08-03 20:03:17.734852	0.60	8475.00
1958	\N	53	2025-02-27	7342.64	1	2025-08-03 20:03:17.996231	2025-08-03 20:03:17.996231	0.59	4300.00
1959	\N	44	2025-02-28	10370.00	1	2025-08-03 20:03:18.215684	2025-08-03 20:03:18.215684	0.30	3145.26
1960	\N	44	2025-02-28	6219.89	1	2025-08-03 20:03:18.482233	2025-08-03 20:03:18.482233	0.70	4353.92
1961	\N	71	2025-02-28	3914.01	1	2025-08-03 20:03:18.785375	2025-08-03 20:03:18.785375	0.45	1761.30
1962	\N	193	2025-02-28	6555.00	1	2025-08-03 20:03:19.175991	2025-08-03 20:03:19.175991	0.56	3661.94
1963	\N	48	2025-02-28	13660.78	1	2025-08-03 20:03:19.437804	2025-08-03 20:03:19.437804	0.44	6000.00
1964	\N	55	2025-02-28	4745.00	1	2025-08-03 20:03:19.702925	2025-08-03 20:03:19.702925	0.50	2372.50
1965	\N	108	2025-02-28	15842.47	1	2025-08-03 20:03:19.963104	2025-08-03 20:03:19.963104	0.40	6336.99
1966	\N	116	2025-02-28	8845.00	1	2025-08-03 20:03:20.190544	2025-08-03 20:03:20.190544	0.51	4510.59
1967	\N	116	2025-02-28	10788.05	1	2025-08-03 20:03:20.454091	2025-08-03 20:03:20.454091	0.38	4099.44
1968	\N	57	2025-02-28	2153.65	1	2025-08-03 20:03:20.70738	2025-08-03 20:03:20.70738	0.60	1292.19
1969	\N	57	2025-02-28	8727.00	1	2025-08-03 20:03:20.975798	2025-08-03 20:03:20.975798	0.55	4799.85
1970	\N	57	2025-02-28	4480.00	1	2025-08-03 20:03:21.227851	2025-08-03 20:03:21.227851	0.49	2200.00
1971	\N	57	2025-02-28	12415.00	1	2025-08-03 20:03:21.438786	2025-08-03 20:03:21.438786	0.50	6207.50
1972	\N	57	2025-02-28	6210.00	1	2025-08-03 20:03:21.700701	2025-08-03 20:03:21.700701	0.55	3415.50
1973	\N	57	2025-02-28	6520.00	1	2025-08-03 20:03:21.952188	2025-08-03 20:03:21.952188	0.55	3600.00
1974	\N	57	2025-02-28	17258.00	1	2025-08-03 20:03:22.173588	2025-08-03 20:03:22.173588	0.43	7350.00
1975	\N	57	2025-02-28	17258.00	1	2025-08-03 20:03:22.4291	2025-08-03 20:03:22.4291	0.43	7350.00
1976	\N	44	2025-03-03	9314.71	1	2025-08-03 20:03:22.679933	2025-08-03 20:03:22.679933	0.60	5588.83
1977	\N	44	2025-03-03	7520.94	1	2025-08-03 20:03:23.034485	2025-08-03 20:03:23.034485	0.60	4512.57
1978	\N	55	2025-03-03	9728.57	1	2025-08-03 20:03:23.244581	2025-08-03 20:03:23.244581	0.35	3405.00
1979	\N	110	2025-03-03	7335.00	1	2025-08-03 20:03:23.499224	2025-08-03 20:03:23.499224	0.50	3667.50
1980	\N	52	2025-03-03	3048.11	1	2025-08-03 20:03:23.75163	2025-08-03 20:03:23.75163	0.50	1524.00
1981	\N	116	2025-03-03	10788.05	1	2025-08-03 20:03:24.004698	2025-08-03 20:03:24.004698	0.38	4099.44
1982	\N	57	2025-03-03	13883.92	1	2025-08-03 20:03:24.24968	2025-08-03 20:03:24.24968	0.55	7600.00
1983	\N	53	2025-03-03	7542.69	1	2025-08-03 20:03:24.499636	2025-08-03 20:03:24.499636	0.70	5270.00
1984	\N	44	2025-03-04	1190.00	1	2025-08-03 20:03:24.760477	2025-08-03 20:03:24.760477	0.50	595.00
1985	\N	44	2025-03-04	9068.55	1	2025-08-03 20:03:25.017739	2025-08-03 20:03:25.017739	0.42	3837.42
1986	\N	44	2025-03-04	5700.00	1	2025-08-03 20:03:25.274643	2025-08-03 20:03:25.274643	0.45	2566.66
1987	\N	44	2025-03-04	11348.71	1	2025-08-03 20:03:25.53831	2025-08-03 20:03:25.53831	0.42	4774.62
1988	\N	44	2025-03-04	4519.70	1	2025-08-03 20:03:25.799044	2025-08-03 20:03:25.799044	0.70	3163.79
1989	\N	44	2025-03-04	7446.14	1	2025-08-03 20:03:26.070854	2025-08-03 20:03:26.070854	0.58	4327.33
1990	\N	44	2025-03-04	7535.00	1	2025-08-03 20:03:26.33183	2025-08-03 20:03:26.33183	0.67	5035.00
1991	\N	55	2025-03-04	3301.19	1	2025-08-03 20:03:26.561099	2025-08-03 20:03:26.561099	0.78	2591.17
1992	\N	110	2025-03-04	9705.00	1	2025-08-03 20:03:26.843057	2025-08-03 20:03:26.843057	0.00	0.00
1993	\N	110	2025-03-04	5415.00	1	2025-08-03 20:03:27.061181	2025-08-03 20:03:27.061181	0.60	3249.00
1994	\N	52	2025-03-04	12064.02	1	2025-08-03 20:03:27.321773	2025-08-03 20:03:27.321773	0.50	6032.00
1995	\N	57	2025-03-04	17258.00	1	2025-08-03 20:03:27.58299	2025-08-03 20:03:27.58299	0.43	7350.00
1996	\N	57	2025-03-04	13716.53	1	2025-08-03 20:03:27.827204	2025-08-03 20:03:27.827204	0.59	8050.00
1997	\N	57	2025-03-04	4460.00	1	2025-08-03 20:03:28.058846	2025-08-03 20:03:28.058846	0.56	2479.50
1998	\N	57	2025-03-04	776.75	1	2025-08-03 20:03:28.279486	2025-08-03 20:03:28.279486	0.55	427.21
1999	\N	57	2025-03-04	881.90	1	2025-08-03 20:03:28.525519	2025-08-03 20:03:28.525519	0.55	485.04
2000	\N	57	2025-03-04	8999.90	1	2025-08-03 20:03:28.774758	2025-08-03 20:03:28.774758	0.60	5399.94
2001	\N	57	2025-03-04	10117.64	1	2025-08-03 20:03:29.037402	2025-08-03 20:03:29.037402	0.57	5800.00
2002	\N	53	2025-03-04	4654.33	1	2025-08-03 20:03:29.290487	2025-08-03 20:03:29.290487	0.52	2400.00
2003	\N	124	2025-03-05	3635.00	1	2025-08-03 20:03:29.538411	2025-08-03 20:03:29.538411	0.55	1999.25
2004	\N	43	2025-03-05	8148.95	1	2025-08-03 20:03:29.764763	2025-08-03 20:03:29.764763	0.62	5020.00
2005	\N	44	2025-03-05	1485.00	1	2025-08-03 20:03:30.015548	2025-08-03 20:03:30.015548	0.70	1039.50
2006	\N	44	2025-03-05	4170.75	1	2025-08-03 20:03:30.274921	2025-08-03 20:03:30.274921	0.60	2502.45
2007	\N	44	2025-03-05	7677.30	1	2025-08-03 20:03:30.537747	2025-08-03 20:03:30.537747	0.19	1487.01
2008	\N	44	2025-03-05	10568.96	1	2025-08-03 20:03:30.791371	2025-08-03 20:03:30.791371	0.70	7398.27
2009	\N	151	2025-03-05	2405.00	1	2025-08-03 20:03:31.055913	2025-08-03 20:03:31.055913	0.49	1166.67
2010	\N	121	2025-03-05	11165.57	1	2025-08-03 20:03:31.303787	2025-08-03 20:03:31.303787	0.50	5582.78
2011	\N	102	2025-03-05	6170.00	1	2025-08-03 20:03:31.65743	2025-08-03 20:03:31.65743	0.65	4010.50
2012	\N	52	2025-03-05	12595.15	1	2025-08-03 20:03:31.998576	2025-08-03 20:03:31.998576	0.50	6298.00
2013	\N	57	2025-03-05	6465.42	1	2025-08-03 20:03:32.261948	2025-08-03 20:03:32.261948	0.56	3643.48
2014	\N	57	2025-03-05	8775.00	1	2025-08-03 20:03:32.625509	2025-08-03 20:03:32.625509	0.50	4387.50
2015	\N	57	2025-03-05	10370.00	1	2025-08-03 20:03:32.925383	2025-08-03 20:03:32.925383	0.52	5400.00
2016	\N	57	2025-03-05	10117.64	1	2025-08-03 20:03:33.182239	2025-08-03 20:03:33.182239	0.57	5800.00
2017	\N	57	2025-03-05	7705.00	1	2025-08-03 20:03:33.412105	2025-08-03 20:03:33.412105	0.68	5255.00
2018	\N	57	2025-03-05	3133.84	1	2025-08-03 20:03:33.770058	2025-08-03 20:03:33.770058	0.60	1880.30
2019	\N	57	2025-03-05	16930.67	1	2025-08-03 20:03:34.030333	2025-08-03 20:03:34.030333	0.60	10158.40
2020	\N	57	2025-03-05	9002.50	1	2025-08-03 20:03:34.292102	2025-08-03 20:03:34.292102	0.55	4951.37
2021	\N	57	2025-03-05	10205.00	1	2025-08-03 20:03:34.560637	2025-08-03 20:03:34.560637	0.71	7245.55
2022	\N	57	2025-03-05	8205.00	1	2025-08-03 20:03:34.818972	2025-08-03 20:03:34.818972	0.55	4512.75
2023	\N	53	2025-03-05	5990.00	1	2025-08-03 20:03:35.083648	2025-08-03 20:03:35.083648	0.75	4492.00
2024	\N	57	2025-03-06	4569.11	1	2025-08-03 20:03:35.342639	2025-08-03 20:03:35.342639	0.48	2209.28
2025	\N	44	2025-03-06	8015.37	1	2025-08-03 20:03:35.599543	2025-08-03 20:03:35.599543	0.70	5610.76
2026	\N	44	2025-03-06	1635.60	1	2025-08-03 20:03:35.858748	2025-08-03 20:03:35.858748	0.70	1145.10
2027	\N	44	2025-03-06	9990.00	1	2025-08-03 20:03:36.12023	2025-08-03 20:03:36.12023	0.35	3500.00
2028	\N	151	2025-03-06	2405.00	1	2025-08-03 20:03:36.390329	2025-08-03 20:03:36.390329	0.49	1166.67
2029	\N	45	2025-03-06	8488.87	1	2025-08-03 20:03:36.597214	2025-08-03 20:03:36.597214	0.50	4244.40
2030	\N	206	2025-03-06	1155.00	1	2025-08-03 20:03:37.048622	2025-08-03 20:03:37.048622	0.60	693.00
2031	\N	92	2025-03-06	2070.00	1	2025-08-03 20:03:37.286017	2025-08-03 20:03:37.286017	0.50	1035.00
2032	\N	71	2025-03-06	3914.01	1	2025-08-03 20:03:37.53898	2025-08-03 20:03:37.53898	0.45	1761.30
2033	\N	82	2025-03-06	12095.00	1	2025-08-03 20:03:37.79565	2025-08-03 20:03:37.79565	0.50	6047.50
2034	\N	65	2025-03-06	17300.00	1	2025-08-03 20:03:38.146257	2025-08-03 20:03:38.146257	0.40	7000.00
2035	\N	52	2025-03-06	6303.27	1	2025-08-03 20:03:38.403845	2025-08-03 20:03:38.403845	0.50	3153.00
2036	\N	116	2025-03-06	7846.86	1	2025-08-03 20:03:38.665112	2025-08-03 20:03:38.665112	0.49	3877.57
2037	\N	57	2025-03-06	5910.00	1	2025-08-03 20:03:38.898653	2025-08-03 20:03:38.898653	0.55	3250.50
2038	\N	57	2025-03-06	4230.15	1	2025-08-03 20:03:39.270797	2025-08-03 20:03:39.270797	0.63	2650.00
2039	\N	53	2025-03-06	500.00	1	2025-08-03 20:03:39.632072	2025-08-03 20:03:39.632072	0.20	100.00
2040	\N	53	2025-03-06	6530.00	1	2025-08-03 20:03:39.878358	2025-08-03 20:03:39.878358	0.54	3500.00
2041	\N	44	2025-03-07	6355.00	1	2025-08-03 20:03:40.140946	2025-08-03 20:03:40.140946	0.60	3813.00
2042	\N	44	2025-03-07	16195.65	1	2025-08-03 20:03:40.496159	2025-08-03 20:03:40.496159	0.23	3759.83
2043	\N	45	2025-03-07	6990.00	1	2025-08-03 20:03:40.713426	2025-08-03 20:03:40.713426	0.50	3495.00
2044	\N	80	2025-03-07	3877.60	1	2025-08-03 20:03:40.966591	2025-08-03 20:03:40.966591	0.51	1977.00
2045	\N	78	2025-03-07	11783.03	1	2025-08-03 20:03:41.247112	2025-08-03 20:03:41.247112	0.50	5891.50
2046	\N	102	2025-03-07	9740.00	1	2025-08-03 20:03:41.457414	2025-08-03 20:03:41.457414	0.50	4870.00
2047	\N	207	2025-03-07	6395.00	1	2025-08-03 20:03:41.890166	2025-08-03 20:03:41.890166	0.50	3197.50
2048	\N	57	2025-03-07	11502.14	1	2025-08-03 20:03:42.122608	2025-08-03 20:03:42.122608	0.58	6700.00
2049	\N	57	2025-03-07	8753.03	1	2025-08-03 20:03:42.380996	2025-08-03 20:03:42.380996	0.55	4814.16
2050	\N	57	2025-03-07	10551.81	1	2025-08-03 20:03:42.638587	2025-08-03 20:03:42.638587	0.55	5803.49
2051	\N	57	2025-03-07	11017.15	1	2025-08-03 20:03:42.904795	2025-08-03 20:03:42.904795	0.55	6059.43
2052	\N	57	2025-03-07	7385.00	1	2025-08-03 20:03:43.186132	2025-08-03 20:03:43.186132	0.61	4486.00
2053	\N	57	2025-03-07	9610.00	1	2025-08-03 20:03:43.398639	2025-08-03 20:03:43.398639	0.52	5000.00
2054	\N	57	2025-03-07	6059.35	1	2025-08-03 20:03:43.652365	2025-08-03 20:03:43.652365	0.60	3635.61
2055	\N	57	2025-03-07	12170.00	1	2025-08-03 20:03:43.892431	2025-08-03 20:03:43.892431	0.60	7302.00
2056	\N	57	2025-03-07	8260.00	1	2025-08-03 20:03:44.15305	2025-08-03 20:03:44.15305	0.61	5049.15
2057	\N	57	2025-03-07	11054.10	1	2025-08-03 20:03:44.413377	2025-08-03 20:03:44.413377	0.60	6632.46
2058	\N	57	2025-03-07	9586.07	1	2025-08-03 20:03:44.66744	2025-08-03 20:03:44.66744	0.60	5751.64
2059	\N	57	2025-03-07	12051.01	1	2025-08-03 20:03:44.909819	2025-08-03 20:03:44.909819	0.50	5975.00
2060	\N	53	2025-03-07	560.00	1	2025-08-03 20:03:45.114219	2025-08-03 20:03:45.114219	0.71	400.00
2061	\N	44	2025-03-10	5575.00	1	2025-08-03 20:03:45.37369	2025-08-03 20:03:45.37369	0.70	3902.50
2062	\N	44	2025-03-10	1610.45	1	2025-08-03 20:03:45.72908	2025-08-03 20:03:45.72908	0.62	996.27
2063	\N	100	2025-03-10	10146.89	1	2025-08-03 20:03:46.087552	2025-08-03 20:03:46.087552	0.50	5073.00
2064	\N	88	2025-03-10	11581.86	1	2025-08-03 20:03:46.371378	2025-08-03 20:03:46.371378	0.63	7324.62
2065	\N	81	2025-03-10	11369.66	1	2025-08-03 20:03:46.626984	2025-08-03 20:03:46.626984	0.55	6253.31
2066	\N	66	2025-03-10	1740.00	1	2025-08-03 20:03:46.878392	2025-08-03 20:03:46.878392	0.67	1166.67
2067	\N	66	2025-03-10	1795.00	1	2025-08-03 20:03:47.151257	2025-08-03 20:03:47.151257	0.60	1083.33
2068	\N	66	2025-03-10	7785.32	1	2025-08-03 20:03:47.402773	2025-08-03 20:03:47.402773	0.61	4741.91
2069	\N	48	2025-03-10	6842.10	1	2025-08-03 20:03:47.674199	2025-08-03 20:03:47.674199	0.60	4105.26
2070	\N	131	2025-03-10	1910.00	1	2025-08-03 20:03:47.941782	2025-08-03 20:03:47.941782	0.48	907.25
2071	\N	142	2025-03-10	9415.00	1	2025-08-03 20:03:48.206398	2025-08-03 20:03:48.206398	0.50	4707.50
2072	\N	110	2025-03-10	10475.00	1	2025-08-03 20:03:48.461737	2025-08-03 20:03:48.461737	0.50	5237.50
2073	\N	116	2025-03-10	5615.00	1	2025-08-03 20:03:48.725248	2025-08-03 20:03:48.725248	0.41	2302.15
2074	\N	208	2025-03-10	7092.42	1	2025-08-03 20:03:49.324228	2025-08-03 20:03:49.324228	0.70	4964.69
2075	\N	57	2025-03-10	3985.00	1	2025-08-03 20:03:49.582916	2025-08-03 20:03:49.582916	0.55	2191.75
2076	\N	99	2025-03-10	2425.00	1	2025-08-03 20:03:49.95078	2025-08-03 20:03:49.95078	0.50	1212.50
2077	\N	44	2025-03-11	2784.50	1	2025-08-03 20:03:50.263457	2025-08-03 20:03:50.263457	0.70	1949.15
2078	\N	44	2025-03-11	1294.15	1	2025-08-03 20:03:50.519938	2025-08-03 20:03:50.519938	0.70	905.90
2079	\N	209	2025-03-11	11160.00	1	2025-08-03 20:03:50.971131	2025-08-03 20:03:50.971131	0.00	0.00
2080	\N	94	2025-03-11	15100.00	1	2025-08-03 20:03:51.235207	2025-08-03 20:03:51.235207	0.65	9815.00
2081	\N	162	2025-03-11	13455.00	1	2025-08-03 20:03:51.488984	2025-08-03 20:03:51.488984	0.50	6727.50
2082	\N	83	2025-03-11	5490.00	1	2025-08-03 20:03:51.759541	2025-08-03 20:03:51.759541	0.49	2664.20
2083	\N	84	2025-03-11	2975.00	1	2025-08-03 20:03:52.016122	2025-08-03 20:03:52.016122	0.61	1800.00
2084	\N	116	2025-03-11	5650.00	1	2025-08-03 20:03:52.318995	2025-08-03 20:03:52.318995	0.81	4600.00
2085	\N	210	2025-03-11	3515.00	1	2025-08-03 20:03:52.750511	2025-08-03 20:03:52.750511	0.95	3350.00
2086	\N	57	2025-03-11	5685.00	1	2025-08-03 20:03:52.961395	2025-08-03 20:03:52.961395	0.61	3469.50
2087	\N	57	2025-03-11	500.00	1	2025-08-03 20:03:53.211797	2025-08-03 20:03:53.211797	0.25	125.00
2088	\N	57	2025-03-11	3540.00	1	2025-08-03 20:03:53.478171	2025-08-03 20:03:53.478171	0.65	2301.00
2089	\N	44	2025-03-12	2754.55	1	2025-08-03 20:03:53.727334	2025-08-03 20:03:53.727334	0.70	1928.18
2090	\N	44	2025-03-12	12268.40	1	2025-08-03 20:03:54.06266	2025-08-03 20:03:54.06266	0.60	7333.33
2091	\N	44	2025-03-12	11142.22	1	2025-08-03 20:03:54.278384	2025-08-03 20:03:54.278384	0.60	6685.34
2092	\N	44	2025-03-12	2706.43	1	2025-08-03 20:03:54.533374	2025-08-03 20:03:54.533374	0.70	1894.51
2093	\N	88	2025-03-12	8190.00	1	2025-08-03 20:03:54.789058	2025-08-03 20:03:54.789058	0.51	4166.67
2094	\N	66	2025-03-12	2415.00	1	2025-08-03 20:03:55.047873	2025-08-03 20:03:55.047873	0.62	1501.17
2095	\N	66	2025-03-12	8631.30	1	2025-08-03 20:03:55.291726	2025-08-03 20:03:55.291726	0.45	3884.09
2096	\N	48	2025-03-12	8005.15	1	2025-08-03 20:03:55.541569	2025-08-03 20:03:55.541569	0.60	4803.09
2097	\N	55	2025-03-12	4860.00	1	2025-08-03 20:03:55.753047	2025-08-03 20:03:55.753047	0.50	2430.00
2098	\N	55	2025-03-12	5618.99	1	2025-08-03 20:03:56.011094	2025-08-03 20:03:56.011094	0.60	3371.39
2099	\N	55	2025-03-12	8732.00	1	2025-08-03 20:03:56.26196	2025-08-03 20:03:56.26196	0.45	3929.40
2100	\N	55	2025-03-12	6063.78	1	2025-08-03 20:03:56.602824	2025-08-03 20:03:56.602824	0.35	2122.32
2101	\N	84	2025-03-12	16765.00	1	2025-08-03 20:03:56.852648	2025-08-03 20:03:56.852648	0.62	10400.00
2102	\N	57	2025-03-12	13771.31	1	2025-08-03 20:03:57.06993	2025-08-03 20:03:57.06993	0.54	7398.92
2103	\N	57	2025-03-12	1808.75	1	2025-08-03 20:03:57.327814	2025-08-03 20:03:57.327814	0.55	994.81
2104	\N	44	2025-03-13	1820.00	1	2025-08-03 20:03:57.589654	2025-08-03 20:03:57.589654	0.70	1274.00
2105	\N	44	2025-03-13	12565.86	1	2025-08-03 20:03:57.842941	2025-08-03 20:03:57.842941	0.73	9146.67
2106	\N	44	2025-03-13	11040.84	1	2025-08-03 20:03:58.214009	2025-08-03 20:03:58.214009	0.70	7728.59
2107	\N	44	2025-03-13	7376.42	1	2025-08-03 20:03:58.430051	2025-08-03 20:03:58.430051	0.66	4876.42
2108	\N	44	2025-03-13	1940.00	1	2025-08-03 20:03:58.697271	2025-08-03 20:03:58.697271	0.62	1204.98
2109	\N	206	2025-03-13	10525.00	1	2025-08-03 20:03:59.092384	2025-08-03 20:03:59.092384	0.65	6841.25
2110	\N	211	2025-03-13	12045.00	1	2025-08-03 20:03:59.509736	2025-08-03 20:03:59.509736	0.55	6624.75
2111	\N	211	2025-03-13	11995.00	1	2025-08-03 20:03:59.717447	2025-08-03 20:03:59.717447	0.55	6597.25
2112	\N	88	2025-03-13	7700.00	1	2025-08-03 20:03:59.936561	2025-08-03 20:03:59.936561	0.42	3234.00
2113	\N	103	2025-03-13	8461.95	1	2025-08-03 20:04:00.198653	2025-08-03 20:04:00.198653	0.67	5700.00
2114	\N	66	2025-03-13	5425.49	1	2025-08-03 20:04:00.558568	2025-08-03 20:04:00.558568	0.55	2984.02
2115	\N	55	2025-03-13	2398.41	1	2025-08-03 20:04:00.814311	2025-08-03 20:04:00.814311	0.60	1439.04
2116	\N	57	2025-03-13	8910.00	1	2025-08-03 20:04:01.071916	2025-08-03 20:04:01.071916	0.60	5346.00
2117	\N	57	2025-03-13	9485.00	1	2025-08-03 20:04:01.447903	2025-08-03 20:04:01.447903	0.51	4800.00
2118	\N	53	2025-03-13	8265.13	1	2025-08-03 20:04:01.70554	2025-08-03 20:04:01.70554	0.69	5700.00
2119	\N	44	2025-03-14	6928.65	1	2025-08-03 20:04:01.966568	2025-08-03 20:04:01.966568	0.70	4850.06
2120	\N	44	2025-03-14	8709.76	1	2025-08-03 20:04:02.33004	2025-08-03 20:04:02.33004	0.63	5485.00
2121	\N	44	2025-03-14	4311.78	1	2025-08-03 20:04:02.560796	2025-08-03 20:04:02.560796	0.60	2587.07
2122	\N	44	2025-03-14	11415.00	1	2025-08-03 20:04:02.811139	2025-08-03 20:04:02.811139	0.63	7200.00
2123	\N	44	2025-03-14	6169.82	1	2025-08-03 20:04:03.066653	2025-08-03 20:04:03.066653	0.30	1836.66
2124	\N	44	2025-03-14	5444.09	1	2025-08-03 20:04:03.333123	2025-08-03 20:04:03.333123	0.48	2590.71
2125	\N	44	2025-03-14	4432.38	1	2025-08-03 20:04:03.602373	2025-08-03 20:04:03.602373	0.46	2020.00
2126	\N	80	2025-03-14	5567.10	1	2025-08-03 20:04:03.822197	2025-08-03 20:04:03.822197	0.45	2505.20
2127	\N	212	2025-03-14	2965.65	1	2025-08-03 20:04:04.265807	2025-08-03 20:04:04.265807	0.50	1482.83
2128	\N	213	2025-03-14	9370.00	1	2025-08-03 20:04:04.678689	2025-08-03 20:04:04.678689	0.60	5622.00
2129	\N	55	2025-03-14	10285.00	1	2025-08-03 20:04:04.88896	2025-08-03 20:04:04.88896	0.50	5142.50
2130	\N	116	2025-03-14	7881.25	1	2025-08-03 20:04:05.151119	2025-08-03 20:04:05.151119	0.51	4000.00
2131	\N	44	2025-03-17	13246.19	1	2025-08-03 20:04:05.502554	2025-08-03 20:04:05.502554	0.47	6167.73
2132	\N	44	2025-03-17	13600.73	1	2025-08-03 20:04:05.85732	2025-08-03 20:04:05.85732	0.29	4000.00
2133	\N	44	2025-03-17	2620.00	1	2025-08-03 20:04:06.112548	2025-08-03 20:04:06.112548	0.62	1628.49
2134	\N	44	2025-03-17	1808.75	1	2025-08-03 20:04:06.368189	2025-08-03 20:04:06.368189	0.39	700.00
2135	\N	44	2025-03-17	1100.00	1	2025-08-03 20:04:06.585693	2025-08-03 20:04:06.585693	0.70	770.00
2136	\N	208	2025-03-17	8011.97	1	2025-08-03 20:04:06.937966	2025-08-03 20:04:06.937966	0.68	5415.45
2137	\N	57	2025-03-17	4500.00	1	2025-08-03 20:04:07.189272	2025-08-03 20:04:07.189272	0.55	2475.00
2138	\N	57	2025-03-17	6139.44	1	2025-08-03 20:04:07.44673	2025-08-03 20:04:07.44673	0.60	3682.46
2139	\N	57	2025-03-17	9725.00	1	2025-08-03 20:04:07.801632	2025-08-03 20:04:07.801632	0.27	2600.00
2140	\N	53	2025-03-17	5703.52	1	2025-08-03 20:04:08.054303	2025-08-03 20:04:08.054303	0.53	3000.00
2141	\N	53	2025-03-17	8441.07	1	2025-08-03 20:04:08.318929	2025-08-03 20:04:08.318929	0.75	6300.00
2142	\N	44	2025-03-18	11563.27	1	2025-08-03 20:04:08.549972	2025-08-03 20:04:08.549972	0.65	7563.27
2143	\N	214	2025-03-18	3950.00	1	2025-08-03 20:04:08.998135	2025-08-03 20:04:08.998135	0.60	2370.00
2144	\N	55	2025-03-18	7711.94	1	2025-08-03 20:04:09.234914	2025-08-03 20:04:09.234914	0.60	4627.16
2145	\N	52	2025-03-18	11807.32	1	2025-08-03 20:04:09.49181	2025-08-03 20:04:09.49181	0.50	5905.00
2146	\N	116	2025-03-18	11535.57	1	2025-08-03 20:04:09.748739	2025-08-03 20:04:09.748739	0.50	5767.79
2147	\N	116	2025-03-18	12617.66	1	2025-08-03 20:04:10.003526	2025-08-03 20:04:10.003526	0.50	6308.83
2148	\N	116	2025-03-18	10070.71	1	2025-08-03 20:04:10.222791	2025-08-03 20:04:10.222791	0.50	5035.36
2149	\N	53	2025-03-18	7241.05	1	2025-08-03 20:04:10.470305	2025-08-03 20:04:10.470305	0.59	4300.00
2150	\N	44	2025-03-19	9446.26	1	2025-08-03 20:04:10.689103	2025-08-03 20:04:10.689103	0.70	6612.38
2151	\N	65	2025-03-19	19302.80	1	2025-08-03 20:04:10.943869	2025-08-03 20:04:10.943869	0.55	10616.54
2152	\N	110	2025-03-19	11620.00	1	2025-08-03 20:04:11.20417	2025-08-03 20:04:11.20417	0.55	6391.00
2153	\N	57	2025-03-19	11639.11	1	2025-08-03 20:04:11.497744	2025-08-03 20:04:11.497744	0.41	4800.00
2154	\N	57	2025-03-19	8787.90	1	2025-08-03 20:04:11.759617	2025-08-03 20:04:11.759617	0.60	5270.00
2155	\N	57	2025-03-19	1810.00	1	2025-08-03 20:04:11.987091	2025-08-03 20:04:11.987091	0.50	905.00
2156	\N	44	2025-03-20	5424.30	1	2025-08-03 20:04:12.242436	2025-08-03 20:04:12.242436	0.60	3254.58
2157	\N	44	2025-03-20	14129.13	1	2025-08-03 20:04:12.505208	2025-08-03 20:04:12.505208	0.50	7064.57
2158	\N	44	2025-03-20	12353.20	1	2025-08-03 20:04:12.773621	2025-08-03 20:04:12.773621	0.39	4801.66
2159	\N	44	2025-03-20	7280.00	1	2025-08-03 20:04:13.135537	2025-08-03 20:04:13.135537	0.18	1307.66
2160	\N	44	2025-03-20	11411.17	1	2025-08-03 20:04:13.357166	2025-08-03 20:04:13.357166	0.33	3791.26
2161	\N	44	2025-03-20	11433.02	1	2025-08-03 20:04:13.608089	2025-08-03 20:04:13.608089	0.39	4415.46
2162	\N	44	2025-03-20	1680.00	1	2025-08-03 20:04:13.857767	2025-08-03 20:04:13.857767	0.70	1176.00
2163	\N	44	2025-03-20	9781.08	1	2025-08-03 20:04:14.108915	2025-08-03 20:04:14.108915	0.50	4890.54
2164	\N	44	2025-03-20	13339.77	1	2025-08-03 20:04:14.376629	2025-08-03 20:04:14.376629	0.38	5070.90
2165	\N	215	2025-03-20	2980.00	1	2025-08-03 20:04:14.805313	2025-08-03 20:04:14.805313	0.55	1639.00
2166	\N	80	2025-03-20	5885.00	1	2025-08-03 20:04:15.038963	2025-08-03 20:04:15.038963	0.50	2942.50
2167	\N	122	2025-03-20	8877.01	1	2025-08-03 20:04:15.281402	2025-08-03 20:04:15.281402	0.52	4600.00
2168	\N	55	2025-03-20	2695.00	1	2025-08-03 20:04:15.531406	2025-08-03 20:04:15.531406	0.60	1617.00
2169	\N	52	2025-03-20	8354.19	1	2025-08-03 20:04:15.927755	2025-08-03 20:04:15.927755	0.40	3344.00
2170	\N	57	2025-03-20	11794.09	1	2025-08-03 20:04:16.139767	2025-08-03 20:04:16.139767	0.56	6569.24
2171	\N	57	2025-03-20	14130.00	1	2025-08-03 20:04:16.478616	2025-08-03 20:04:16.478616	0.50	7064.50
2172	\N	57	2025-03-20	1275.15	1	2025-08-03 20:04:16.72723	2025-08-03 20:04:16.72723	0.72	913.13
2173	\N	44	2025-03-21	3517.82	1	2025-08-03 20:04:16.995787	2025-08-03 20:04:16.995787	0.48	1679.50
2174	\N	44	2025-03-21	7976.42	1	2025-08-03 20:04:17.224751	2025-08-03 20:04:17.224751	0.50	3988.21
2175	\N	44	2025-03-21	6190.00	1	2025-08-03 20:04:17.441624	2025-08-03 20:04:17.441624	0.70	4333.00
2176	\N	44	2025-03-21	1366.80	1	2025-08-03 20:04:17.780217	2025-08-03 20:04:17.780217	0.70	956.67
2177	\N	44	2025-03-21	5444.29	1	2025-08-03 20:04:18.04795	2025-08-03 20:04:18.04795	0.46	2513.33
2178	\N	44	2025-03-21	6335.29	1	2025-08-03 20:04:18.303099	2025-08-03 20:04:18.303099	0.41	2596.67
2179	\N	44	2025-03-21	15417.33	1	2025-08-03 20:04:18.577717	2025-08-03 20:04:18.577717	0.35	5446.67
2180	\N	44	2025-03-21	6733.18	1	2025-08-03 20:04:18.802716	2025-08-03 20:04:18.802716	0.38	2583.33
2181	\N	44	2025-03-21	3246.75	1	2025-08-03 20:04:19.059735	2025-08-03 20:04:19.059735	0.60	1948.05
2182	\N	44	2025-03-21	9406.42	1	2025-08-03 20:04:19.324216	2025-08-03 20:04:19.324216	0.60	5643.86
2183	\N	44	2025-03-21	9725.08	1	2025-08-03 20:04:19.537841	2025-08-03 20:04:19.537841	0.39	3814.66
2184	\N	44	2025-03-21	9655.00	1	2025-08-03 20:04:19.774242	2025-08-03 20:04:19.774242	0.70	6758.50
2185	\N	94	2025-03-21	5815.86	1	2025-08-03 20:04:19.997423	2025-08-03 20:04:19.997423	0.70	4071.10
2186	\N	80	2025-03-21	9490.00	1	2025-08-03 20:04:20.196129	2025-08-03 20:04:20.196129	0.60	5694.00
2187	\N	134	2025-03-21	6972.36	1	2025-08-03 20:04:20.448227	2025-08-03 20:04:20.448227	0.60	4183.42
2188	\N	134	2025-03-21	8365.63	1	2025-08-03 20:04:20.69521	2025-08-03 20:04:20.69521	0.60	5019.38
2189	\N	143	2025-03-21	6475.00	1	2025-08-03 20:04:20.944033	2025-08-03 20:04:20.944033	0.50	3237.50
2190	\N	116	2025-03-21	3980.00	1	2025-08-03 20:04:21.21002	2025-08-03 20:04:21.21002	0.55	2189.00
2191	\N	57	2025-03-21	6727.38	1	2025-08-03 20:04:21.470569	2025-08-03 20:04:21.470569	0.65	4372.74
2192	\N	57	2025-03-21	7750.00	1	2025-08-03 20:04:21.720746	2025-08-03 20:04:21.720746	0.60	4650.00
2193	\N	57	2025-03-21	8775.90	1	2025-08-03 20:04:21.970937	2025-08-03 20:04:21.970937	0.69	6066.13
2194	\N	57	2025-03-21	11225.00	1	2025-08-03 20:04:22.228939	2025-08-03 20:04:22.228939	0.58	6550.00
2195	\N	53	2025-03-21	7733.56	1	2025-08-03 20:04:22.496611	2025-08-03 20:04:22.496611	0.65	5000.00
2196	\N	44	2025-03-24	12107.99	1	2025-08-03 20:04:22.737684	2025-08-03 20:04:22.737684	0.56	6791.33
2197	\N	44	2025-03-24	2276.69	1	2025-08-03 20:04:22.946994	2025-08-03 20:04:22.946994	0.70	1593.69
2198	\N	44	2025-03-24	967.72	1	2025-08-03 20:04:23.210658	2025-08-03 20:04:23.210658	0.70	677.40
2199	\N	44	2025-03-24	8425.00	1	2025-08-03 20:04:23.465992	2025-08-03 20:04:23.465992	0.46	3894.33
2200	\N	44	2025-03-24	11704.79	1	2025-08-03 20:04:23.719681	2025-08-03 20:04:23.719681	0.59	6930.07
2201	\N	44	2025-03-24	10673.32	1	2025-08-03 20:04:23.973472	2025-08-03 20:04:23.973472	0.37	3938.41
2202	\N	44	2025-03-24	5790.00	1	2025-08-03 20:04:24.229669	2025-08-03 20:04:24.229669	0.54	3146.90
2203	\N	44	2025-03-24	10220.21	1	2025-08-03 20:04:24.490627	2025-08-03 20:04:24.490627	0.50	5110.11
2204	\N	45	2025-03-24	9430.00	1	2025-08-03 20:04:24.75161	2025-08-03 20:04:24.75161	0.50	4715.00
2205	\N	91	2025-03-24	8885.00	1	2025-08-03 20:04:25.016556	2025-08-03 20:04:25.016556	0.64	5716.75
2206	\N	105	2025-03-24	9740.00	1	2025-08-03 20:04:25.26496	2025-08-03 20:04:25.26496	0.65	6331.00
2207	\N	55	2025-03-24	10083.63	1	2025-08-03 20:04:25.517009	2025-08-03 20:04:25.517009	0.25	2500.00
2208	\N	102	2025-03-24	4630.57	1	2025-08-03 20:04:25.782233	2025-08-03 20:04:25.782233	0.50	2315.29
2209	\N	102	2025-03-24	12505.00	1	2025-08-03 20:04:26.030793	2025-08-03 20:04:26.030793	0.50	6252.50
2210	\N	57	2025-03-24	5170.00	1	2025-08-03 20:04:26.285507	2025-08-03 20:04:26.285507	0.40	2068.00
2211	\N	57	2025-03-24	10690.00	1	2025-08-03 20:04:26.648369	2025-08-03 20:04:26.648369	0.60	6414.00
2212	\N	53	2025-03-24	5356.36	1	2025-08-03 20:04:26.915547	2025-08-03 20:04:26.915547	0.65	3481.00
2213	\N	52	2025-03-25	615.25	1	2025-08-03 20:04:27.173007	2025-08-03 20:04:27.173007	0.50	308.00
2214	\N	44	2025-03-25	7721.15	1	2025-08-03 20:04:27.441864	2025-08-03 20:04:27.441864	0.60	4632.69
2215	\N	44	2025-03-25	1760.00	1	2025-08-03 20:04:27.695094	2025-08-03 20:04:27.695094	0.60	1056.00
2216	\N	44	2025-03-25	8216.16	1	2025-08-03 20:04:27.954053	2025-08-03 20:04:27.954053	0.57	4658.83
2217	\N	45	2025-03-25	2215.27	1	2025-08-03 20:04:28.199735	2025-08-03 20:04:28.199735	0.50	1107.63
2218	\N	88	2025-03-25	12821.89	1	2025-08-03 20:04:28.402544	2025-08-03 20:04:28.402544	0.62	8000.00
2219	\N	102	2025-03-25	10235.00	1	2025-08-03 20:04:28.664191	2025-08-03 20:04:28.664191	0.40	4094.00
2220	\N	84	2025-03-25	2030.00	1	2025-08-03 20:04:28.930691	2025-08-03 20:04:28.930691	0.54	1100.00
2221	\N	52	2025-03-25	2568.00	1	2025-08-03 20:04:29.181368	2025-08-03 20:04:29.181368	0.60	1541.00
2222	\N	52	2025-03-25	4228.62	1	2025-08-03 20:04:29.393655	2025-08-03 20:04:29.393655	0.60	2538.00
2223	\N	116	2025-03-25	6598.22	1	2025-08-03 20:04:29.659585	2025-08-03 20:04:29.659585	0.49	3218.14
2224	\N	57	2025-03-25	4515.00	1	2025-08-03 20:04:29.921086	2025-08-03 20:04:29.921086	0.50	2257.50
2225	\N	57	2025-03-25	12241.55	1	2025-08-03 20:04:30.162992	2025-08-03 20:04:30.162992	0.60	7344.93
2226	\N	57	2025-03-25	10295.00	1	2025-08-03 20:04:30.437642	2025-08-03 20:04:30.437642	0.59	6100.00
2227	\N	60	2025-03-25	3752.00	1	2025-08-03 20:04:30.692914	2025-08-03 20:04:30.692914	0.50	1876.00
2228	\N	44	2025-03-26	11721.27	1	2025-08-03 20:04:30.989544	2025-08-03 20:04:30.989544	0.49	5764.53
2229	\N	44	2025-03-26	14703.56	1	2025-08-03 20:04:31.251902	2025-08-03 20:04:31.251902	0.70	10292.49
2230	\N	44	2025-03-26	4877.90	1	2025-08-03 20:04:31.519421	2025-08-03 20:04:31.519421	0.40	1946.66
2231	\N	44	2025-03-26	5447.67	1	2025-08-03 20:04:31.775226	2025-08-03 20:04:31.775226	0.34	1875.00
2232	\N	197	2025-03-26	7965.00	1	2025-08-03 20:04:32.027292	2025-08-03 20:04:32.027292	0.50	3982.50
2233	\N	197	2025-03-26	7615.00	1	2025-08-03 20:04:32.285429	2025-08-03 20:04:32.285429	0.50	3807.50
2234	\N	127	2025-03-26	8102.70	1	2025-08-03 20:04:32.503796	2025-08-03 20:04:32.503796	0.40	3241.08
2235	\N	127	2025-03-26	7572.44	1	2025-08-03 20:04:32.756695	2025-08-03 20:04:32.756695	0.45	3407.60
2236	\N	216	2025-03-26	10960.00	1	2025-08-03 20:04:33.210991	2025-08-03 20:04:33.210991	0.45	4932.00
2237	\N	124	2025-03-26	23680.00	1	2025-08-03 20:04:33.568334	2025-08-03 20:04:33.568334	0.45	10656.00
2238	\N	52	2025-03-26	2626.84	1	2025-08-03 20:04:33.806058	2025-08-03 20:04:33.806058	0.60	1576.00
2239	\N	52	2025-03-26	4302.67	1	2025-08-03 20:04:34.048985	2025-08-03 20:04:34.048985	0.50	2151.00
2240	\N	208	2025-03-26	11076.76	1	2025-08-03 20:04:34.316331	2025-08-03 20:04:34.316331	0.45	5038.38
2241	\N	57	2025-03-26	4430.55	1	2025-08-03 20:04:34.570037	2025-08-03 20:04:34.570037	0.60	2658.33
2242	\N	57	2025-03-26	13721.06	1	2025-08-03 20:04:34.82093	2025-08-03 20:04:34.82093	0.54	7413.69
2243	\N	57	2025-03-26	6617.24	1	2025-08-03 20:04:35.070532	2025-08-03 20:04:35.070532	0.45	2977.76
2244	\N	57	2025-03-26	12498.93	1	2025-08-03 20:04:35.43032	2025-08-03 20:04:35.43032	0.50	6249.46
2245	\N	44	2025-03-27	7408.74	1	2025-08-03 20:04:35.686015	2025-08-03 20:04:35.686015	0.56	4131.07
2246	\N	44	2025-03-27	8380.85	1	2025-08-03 20:04:35.901813	2025-08-03 20:04:35.901813	0.56	4731.37
2247	\N	44	2025-03-27	4675.00	1	2025-08-03 20:04:36.157349	2025-08-03 20:04:36.157349	0.58	2727.42
2248	\N	191	2025-03-27	13935.00	1	2025-08-03 20:04:36.410721	2025-08-03 20:04:36.410721	0.54	7593.01
2249	\N	217	2025-03-27	12984.13	1	2025-08-03 20:04:36.849557	2025-08-03 20:04:36.849557	0.46	6000.00
2250	\N	80	2025-03-27	5677.10	1	2025-08-03 20:04:37.077704	2025-08-03 20:04:37.077704	0.55	3122.41
2251	\N	55	2025-03-27	8895.00	1	2025-08-03 20:04:37.328549	2025-08-03 20:04:37.328549	0.67	5917.47
2252	\N	55	2025-03-27	2822.56	1	2025-08-03 20:04:37.591682	2025-08-03 20:04:37.591682	0.50	1411.28
2253	\N	55	2025-03-27	11695.00	1	2025-08-03 20:04:37.936938	2025-08-03 20:04:37.936938	0.50	5847.50
2254	\N	55	2025-03-27	11279.02	1	2025-08-03 20:04:38.299512	2025-08-03 20:04:38.299512	0.50	5639.51
2255	\N	57	2025-03-27	14663.99	1	2025-08-03 20:04:38.56736	2025-08-03 20:04:38.56736	0.65	9531.59
2256	\N	57	2025-03-27	10690.00	1	2025-08-03 20:04:38.823299	2025-08-03 20:04:38.823299	0.62	6639.00
2257	\N	57	2025-03-27	11889.80	1	2025-08-03 20:04:39.07828	2025-08-03 20:04:39.07828	0.55	6550.00
2258	\N	57	2025-03-27	15658.44	1	2025-08-03 20:04:39.293387	2025-08-03 20:04:39.293387	0.50	7850.00
2259	\N	57	2025-03-27	2745.00	1	2025-08-03 20:04:39.567849	2025-08-03 20:04:39.567849	0.62	1700.00
2260	\N	57	2025-03-27	10540.00	1	2025-08-03 20:04:39.790997	2025-08-03 20:04:39.790997	0.55	5782.50
2261	\N	57	2025-03-27	550.00	1	2025-08-03 20:04:40.052061	2025-08-03 20:04:40.052061	0.73	400.00
2262	\N	182	2025-03-27	8795.00	1	2025-08-03 20:04:40.308952	2025-08-03 20:04:40.308952	0.55	4837.25
2263	\N	44	2025-03-28	2611.02	1	2025-08-03 20:04:40.690037	2025-08-03 20:04:40.690037	0.70	1827.71
2264	\N	44	2025-03-28	8152.90	1	2025-08-03 20:04:40.9138	2025-08-03 20:04:40.9138	0.21	1751.50
2265	\N	127	2025-03-28	7572.44	1	2025-08-03 20:04:41.168867	2025-08-03 20:04:41.168867	0.45	3407.60
2266	\N	216	2025-03-28	8580.00	1	2025-08-03 20:04:41.420273	2025-08-03 20:04:41.420273	0.45	3861.00
2267	\N	66	2025-03-28	4640.90	1	2025-08-03 20:04:41.7081	2025-08-03 20:04:41.7081	0.60	2784.54
2268	\N	57	2025-03-28	9471.44	1	2025-08-03 20:04:41.977249	2025-08-03 20:04:41.977249	0.65	6156.44
2269	\N	57	2025-03-28	7441.40	1	2025-08-03 20:04:42.240404	2025-08-03 20:04:42.240404	0.60	4464.84
2270	\N	57	2025-03-28	15700.00	1	2025-08-03 20:04:42.598116	2025-08-03 20:04:42.598116	0.60	9420.00
2271	\N	57	2025-03-28	9398.96	1	2025-08-03 20:04:42.85537	2025-08-03 20:04:42.85537	0.60	5639.37
2272	\N	57	2025-03-28	3545.00	1	2025-08-03 20:04:43.118988	2025-08-03 20:04:43.118988	0.58	2069.75
2273	\N	57	2025-03-28	8105.00	1	2025-08-03 20:04:43.372805	2025-08-03 20:04:43.372805	0.56	4521.50
2274	\N	44	2025-04-01	3522.66	1	2025-08-03 20:04:43.704165	2025-08-03 20:04:43.704165	0.45	1585.20
2275	\N	43	2025-04-01	3295.00	1	2025-08-03 20:04:43.975391	2025-08-03 20:04:43.975391	0.60	1977.00
2276	\N	44	2025-04-01	1660.00	1	2025-08-03 20:04:44.229674	2025-08-03 20:04:44.229674	0.40	661.66
2277	\N	44	2025-04-01	8152.90	1	2025-08-03 20:04:44.482387	2025-08-03 20:04:44.482387	0.22	1777.27
2278	\N	44	2025-04-01	7291.50	1	2025-08-03 20:04:44.799406	2025-08-03 20:04:44.799406	0.50	3645.75
2279	\N	44	2025-04-01	2073.65	1	2025-08-03 20:04:45.165113	2025-08-03 20:04:45.165113	0.57	1191.33
2280	\N	44	2025-04-01	7446.85	1	2025-08-03 20:04:45.42182	2025-08-03 20:04:45.42182	0.46	3410.46
2281	\N	44	2025-04-01	7428.96	1	2025-08-03 20:04:45.687948	2025-08-03 20:04:45.687948	0.60	4457.38
2282	\N	44	2025-04-01	10395.00	1	2025-08-03 20:04:45.940551	2025-08-03 20:04:45.940551	0.50	5197.50
2283	\N	218	2025-04-01	8420.00	1	2025-08-03 20:04:46.444985	2025-08-03 20:04:46.444985	0.55	4631.00
2284	\N	219	2025-04-01	26075.00	1	2025-08-03 20:04:46.907255	2025-08-03 20:04:46.907255	0.52	13639.55
2285	\N	88	2025-04-01	10119.80	1	2025-08-03 20:04:47.127057	2025-08-03 20:04:47.127057	0.73	7387.45
2286	\N	80	2025-04-01	11210.00	1	2025-08-03 20:04:47.412543	2025-08-03 20:04:47.412543	0.20	2242.00
2287	\N	48	2025-04-01	7305.00	1	2025-08-03 20:04:47.661891	2025-08-03 20:04:47.661891	0.59	4300.00
2288	\N	55	2025-04-01	6971.25	1	2025-08-03 20:04:48.030344	2025-08-03 20:04:48.030344	0.50	3485.63
2289	\N	55	2025-04-01	10395.28	1	2025-08-03 20:04:48.32466	2025-08-03 20:04:48.32466	0.50	5197.64
2290	\N	102	2025-04-01	6870.00	1	2025-08-03 20:04:48.618457	2025-08-03 20:04:48.618457	0.50	3435.00
2291	\N	52	2025-04-01	2472.40	1	2025-08-03 20:04:48.850246	2025-08-03 20:04:48.850246	0.50	1242.00
2292	\N	57	2025-04-01	12703.41	1	2025-08-03 20:04:49.114961	2025-08-03 20:04:49.114961	0.60	7622.04
2293	\N	57	2025-04-01	7790.56	1	2025-08-03 20:04:49.362181	2025-08-03 20:04:49.362181	0.50	3895.28
2294	\N	57	2025-04-01	11272.80	1	2025-08-03 20:04:49.635602	2025-08-03 20:04:49.635602	0.62	7033.83
2295	\N	57	2025-04-01	9285.00	1	2025-08-03 20:04:49.922808	2025-08-03 20:04:49.922808	0.71	6585.00
2296	\N	57	2025-04-01	22015.00	1	2025-08-03 20:04:50.17815	2025-08-03 20:04:50.17815	0.63	13925.00
2297	\N	57	2025-04-01	11770.00	1	2025-08-03 20:04:50.721768	2025-08-03 20:04:50.721768	0.60	7062.00
2298	\N	57	2025-04-01	11603.32	1	2025-08-03 20:04:51.044262	2025-08-03 20:04:51.044262	0.50	5801.66
2299	\N	57	2025-04-01	9676.66	1	2025-08-03 20:04:51.31263	2025-08-03 20:04:51.31263	0.50	4838.33
2300	\N	57	2025-04-01	11785.00	1	2025-08-03 20:04:51.621596	2025-08-03 20:04:51.621596	0.60	7071.00
2301	\N	60	2025-04-01	6831.45	1	2025-08-03 20:04:51.91161	2025-08-03 20:04:51.91161	0.65	4440.45
2302	\N	53	2025-04-01	6562.73	1	2025-08-03 20:04:52.198039	2025-08-03 20:04:52.198039	0.70	4600.00
2303	\N	53	2025-04-01	8100.00	1	2025-08-03 20:04:52.481536	2025-08-03 20:04:52.481536	0.56	4500.00
2304	\N	44	2025-04-02	5231.81	1	2025-08-03 20:04:52.779928	2025-08-03 20:04:52.779928	0.52	2743.94
2305	\N	44	2025-04-02	11144.77	1	2025-08-03 20:04:53.08158	2025-08-03 20:04:53.08158	0.60	6686.86
2306	\N	165	2025-04-02	11817.22	1	2025-08-03 20:04:53.371161	2025-08-03 20:04:53.371161	0.40	4726.89
2307	\N	88	2025-04-02	9175.00	1	2025-08-03 20:04:53.674235	2025-08-03 20:04:53.674235	0.17	1559.75
2308	\N	88	2025-04-02	7890.00	1	2025-08-03 20:04:54.076023	2025-08-03 20:04:54.076023	0.21	1656.00
2309	\N	202	2025-04-02	6175.00	1	2025-08-03 20:04:54.33801	2025-08-03 20:04:54.33801	0.50	3087.50
2310	\N	48	2025-04-02	11945.96	1	2025-08-03 20:04:54.845927	2025-08-03 20:04:54.845927	0.59	7000.00
2311	\N	48	2025-04-02	10629.71	1	2025-08-03 20:04:55.262598	2025-08-03 20:04:55.262598	0.59	6300.00
2312	\N	44	2025-04-03	4931.83	1	2025-08-03 20:04:55.579791	2025-08-03 20:04:55.579791	0.60	2959.10
2313	\N	44	2025-04-03	8585.00	1	2025-08-03 20:04:55.864868	2025-08-03 20:04:55.864868	0.39	3371.06
2314	\N	44	2025-04-03	2680.00	1	2025-08-03 20:04:56.148959	2025-08-03 20:04:56.148959	0.57	1525.99
2315	\N	44	2025-04-03	1210.45	1	2025-08-03 20:04:56.441231	2025-08-03 20:04:56.441231	0.60	726.27
2316	\N	45	2025-04-03	10034.20	1	2025-08-03 20:04:56.734072	2025-08-03 20:04:56.734072	0.50	5017.10
2317	\N	120	2025-04-03	3088.14	1	2025-08-03 20:04:56.954411	2025-08-03 20:04:56.954411	0.50	1544.07
2318	\N	94	2025-04-03	7913.64	1	2025-08-03 20:04:57.174006	2025-08-03 20:04:57.174006	0.55	4352.50
2319	\N	80	2025-04-03	4278.16	1	2025-08-03 20:04:57.438087	2025-08-03 20:04:57.438087	0.65	2780.80
2320	\N	124	2025-04-03	6230.00	1	2025-08-03 20:04:57.689783	2025-08-03 20:04:57.689783	0.50	3115.00
2321	\N	55	2025-04-03	1083.75	1	2025-08-03 20:04:57.956739	2025-08-03 20:04:57.956739	0.60	650.25
2322	\N	55	2025-04-03	6030.00	1	2025-08-03 20:04:58.21443	2025-08-03 20:04:58.21443	0.50	3015.00
2323	\N	55	2025-04-03	2677.92	1	2025-08-03 20:04:58.451829	2025-08-03 20:04:58.451829	0.60	1606.75
2324	\N	55	2025-04-03	6340.00	1	2025-08-03 20:04:58.714587	2025-08-03 20:04:58.714587	0.40	2536.00
2325	\N	55	2025-04-03	6322.63	1	2025-08-03 20:04:58.970505	2025-08-03 20:04:58.970505	0.50	3161.31
2326	\N	52	2025-04-03	3990.64	1	2025-08-03 20:04:59.257334	2025-08-03 20:04:59.257334	0.50	1996.00
2327	\N	57	2025-04-03	9258.09	1	2025-08-03 20:04:59.522123	2025-08-03 20:04:59.522123	0.56	5146.78
2328	\N	57	2025-04-03	12842.37	1	2025-08-03 20:04:59.743854	2025-08-03 20:04:59.743854	0.35	4494.83
2329	\N	57	2025-04-03	950.00	1	2025-08-03 20:04:59.986791	2025-08-03 20:04:59.986791	0.60	570.00
2330	\N	57	2025-04-03	6067.92	1	2025-08-03 20:05:00.263155	2025-08-03 20:05:00.263155	0.60	3640.00
2331	\N	57	2025-04-03	5138.55	1	2025-08-03 20:05:00.534246	2025-08-03 20:05:00.534246	0.60	3080.00
2332	\N	53	2025-04-03	4561.00	1	2025-08-03 20:05:00.917579	2025-08-03 20:05:00.917579	0.33	1500.00
2333	\N	44	2025-04-04	11720.64	1	2025-08-03 20:05:01.136172	2025-08-03 20:05:01.136172	0.31	3624.70
2334	\N	44	2025-04-04	14383.58	1	2025-08-03 20:05:01.379053	2025-08-03 20:05:01.379053	0.60	8630.14
2335	\N	44	2025-04-04	6605.40	1	2025-08-03 20:05:01.722746	2025-08-03 20:05:01.722746	0.60	3963.24
2336	\N	44	2025-04-04	11795.46	1	2025-08-03 20:05:02.03476	2025-08-03 20:05:02.03476	0.60	7077.28
2337	\N	44	2025-04-04	9598.76	1	2025-08-03 20:05:02.264383	2025-08-03 20:05:02.264383	0.60	5759.26
2338	\N	71	2025-04-04	5900.00	1	2025-08-03 20:05:02.442804	2025-08-03 20:05:02.442804	0.52	3089.75
2339	\N	80	2025-04-04	6820.00	1	2025-08-03 20:05:02.628888	2025-08-03 20:05:02.628888	0.39	2688.00
2340	\N	48	2025-04-04	8223.08	1	2025-08-03 20:05:02.843602	2025-08-03 20:05:02.843602	0.60	4933.85
2341	\N	108	2025-04-04	8245.00	1	2025-08-03 20:05:03.083765	2025-08-03 20:05:03.083765	0.35	2885.75
2342	\N	108	2025-04-04	7010.00	1	2025-08-03 20:05:03.322608	2025-08-03 20:05:03.322608	0.35	2453.50
2343	\N	52	2025-04-04	4309.50	1	2025-08-03 20:05:03.562882	2025-08-03 20:05:03.562882	0.50	2156.00
2344	\N	57	2025-04-04	10245.00	1	2025-08-03 20:05:03.773336	2025-08-03 20:05:03.773336	0.67	6845.00
2345	\N	57	2025-04-04	11071.99	1	2025-08-03 20:05:04.01118	2025-08-03 20:05:04.01118	0.60	6643.19
2346	\N	57	2025-04-04	15384.70	1	2025-08-03 20:05:04.247061	2025-08-03 20:05:04.247061	0.49	7550.00
2347	\N	44	2025-04-07	9085.00	1	2025-08-03 20:05:04.493805	2025-08-03 20:05:04.493805	0.70	6359.50
2348	\N	44	2025-04-07	7732.62	1	2025-08-03 20:05:04.723708	2025-08-03 20:05:04.723708	0.35	2699.29
2349	\N	44	2025-04-07	7581.74	1	2025-08-03 20:05:04.950048	2025-08-03 20:05:04.950048	0.30	2274.53
2350	\N	45	2025-04-07	1190.00	1	2025-08-03 20:05:05.135809	2025-08-03 20:05:05.135809	0.50	595.00
2351	\N	66	2025-04-07	10171.83	1	2025-08-03 20:05:05.480801	2025-08-03 20:05:05.480801	0.54	5494.51
2352	\N	52	2025-04-07	8845.00	1	2025-08-03 20:05:05.713638	2025-08-03 20:05:05.713638	0.30	2654.00
2353	\N	52	2025-04-07	10934.11	1	2025-08-03 20:05:06.087272	2025-08-03 20:05:06.087272	0.60	6561.00
2354	\N	220	2025-04-07	16950.00	1	2025-08-03 20:05:06.483171	2025-08-03 20:05:06.483171	0.50	8475.00
2355	\N	57	2025-04-07	12770.49	1	2025-08-03 20:05:06.688736	2025-08-03 20:05:06.688736	0.50	6385.24
2356	\N	57	2025-04-07	9289.00	1	2025-08-03 20:05:06.939462	2025-08-03 20:05:06.939462	0.40	3715.60
2357	\N	57	2025-04-07	12890.00	1	2025-08-03 20:05:07.20924	2025-08-03 20:05:07.20924	0.50	6445.00
2358	\N	60	2025-04-07	11687.55	1	2025-08-03 20:05:07.469056	2025-08-03 20:05:07.469056	0.50	5843.78
2359	\N	60	2025-04-07	4620.00	1	2025-08-03 20:05:07.717683	2025-08-03 20:05:07.717683	0.50	2310.00
2360	\N	53	2025-04-07	5554.60	1	2025-08-03 20:05:07.911008	2025-08-03 20:05:07.911008	0.72	4000.00
2361	\N	45	2025-04-08	7465.00	1	2025-08-03 20:05:08.142156	2025-08-03 20:05:08.142156	0.50	3732.50
2362	\N	94	2025-04-08	717.95	1	2025-08-03 20:05:08.396151	2025-08-03 20:05:08.396151	0.60	430.05
2363	\N	80	2025-04-08	685.00	1	2025-08-03 20:05:08.64155	2025-08-03 20:05:08.64155	0.60	411.00
2364	\N	58	2025-04-08	10976.59	1	2025-08-03 20:05:08.993704	2025-08-03 20:05:08.993704	0.70	7738.00
2365	\N	66	2025-04-08	16450.19	1	2025-08-03 20:05:09.324918	2025-08-03 20:05:09.324918	0.50	8225.10
2366	\N	66	2025-04-08	8778.45	1	2025-08-03 20:05:09.685896	2025-08-03 20:05:09.685896	0.55	4828.15
2367	\N	52	2025-04-08	15322.05	1	2025-08-03 20:05:09.916125	2025-08-03 20:05:09.916125	0.50	7662.00
2368	\N	57	2025-04-08	7557.31	1	2025-08-03 20:05:10.256469	2025-08-03 20:05:10.256469	0.50	3778.65
2369	\N	57	2025-04-08	5138.55	1	2025-08-03 20:05:10.501391	2025-08-03 20:05:10.501391	0.60	3080.00
2370	\N	57	2025-04-08	905.00	1	2025-08-03 20:05:10.741473	2025-08-03 20:05:10.741473	0.60	543.00
2371	\N	60	2025-04-08	5689.10	1	2025-08-03 20:05:11.067932	2025-08-03 20:05:11.067932	0.65	3697.92
2372	\N	44	2025-04-09	7308.15	1	2025-08-03 20:05:11.282192	2025-08-03 20:05:11.282192	0.47	3444.56
2373	\N	44	2025-04-09	5254.95	1	2025-08-03 20:05:11.51608	2025-08-03 20:05:11.51608	0.70	3678.46
2374	\N	102	2025-04-09	11448.94	1	2025-08-03 20:05:11.758372	2025-08-03 20:05:11.758372	0.75	8586.00
2375	\N	108	2025-04-09	7584.45	1	2025-08-03 20:05:11.956754	2025-08-03 20:05:11.956754	0.35	2654.00
2376	\N	57	2025-04-09	10945.00	1	2025-08-03 20:05:12.183875	2025-08-03 20:05:12.183875	0.50	5472.50
2377	\N	57	2025-04-09	9194.49	1	2025-08-03 20:05:12.404952	2025-08-03 20:05:12.404952	0.60	5525.00
2378	\N	57	2025-04-09	12682.83	1	2025-08-03 20:05:12.63763	2025-08-03 20:05:12.63763	0.58	7410.00
2379	\N	44	2025-04-10	9946.06	1	2025-08-03 20:05:12.874289	2025-08-03 20:05:12.874289	0.64	6360.00
2380	\N	44	2025-04-10	3272.60	1	2025-08-03 20:05:13.104608	2025-08-03 20:05:13.104608	0.41	1345.00
2381	\N	44	2025-04-10	5577.25	1	2025-08-03 20:05:13.316476	2025-08-03 20:05:13.316476	0.60	3346.35
2382	\N	44	2025-04-10	7755.00	1	2025-08-03 20:05:13.539882	2025-08-03 20:05:13.539882	0.48	3711.13
2383	\N	44	2025-04-10	6478.71	1	2025-08-03 20:05:13.872404	2025-08-03 20:05:13.872404	0.44	2833.33
2384	\N	127	2025-04-10	1490.00	1	2025-08-03 20:05:14.100864	2025-08-03 20:05:14.100864	0.55	819.50
2385	\N	150	2025-04-10	7085.00	1	2025-08-03 20:05:14.319635	2025-08-03 20:05:14.319635	0.50	3542.50
2386	\N	150	2025-04-10	5945.00	1	2025-08-03 20:05:14.634094	2025-08-03 20:05:14.634094	0.50	2972.50
2387	\N	80	2025-04-10	11775.00	1	2025-08-03 20:05:14.859114	2025-08-03 20:05:14.859114	0.65	7653.75
2388	\N	55	2025-04-10	5195.00	1	2025-08-03 20:05:15.08445	2025-08-03 20:05:15.08445	0.50	2597.50
2389	\N	55	2025-04-10	7036.90	1	2025-08-03 20:05:15.314456	2025-08-03 20:05:15.314456	0.50	3518.45
2390	\N	55	2025-04-10	4430.00	1	2025-08-03 20:05:15.531311	2025-08-03 20:05:15.531311	0.50	2215.00
2391	\N	55	2025-04-10	6272.47	1	2025-08-03 20:05:15.739281	2025-08-03 20:05:15.739281	0.50	3136.23
2392	\N	55	2025-04-10	2983.97	1	2025-08-03 20:05:15.954998	2025-08-03 20:05:15.954998	0.50	1491.99
2393	\N	55	2025-04-10	5419.39	1	2025-08-03 20:05:16.132584	2025-08-03 20:05:16.132584	0.30	1625.82
2394	\N	221	2025-04-10	7440.00	1	2025-08-03 20:05:16.642226	2025-08-03 20:05:16.642226	0.81	6000.00
2395	\N	110	2025-04-10	8030.00	1	2025-08-03 20:05:16.933304	2025-08-03 20:05:16.933304	0.50	4015.00
2396	\N	57	2025-04-10	10155.00	1	2025-08-03 20:05:17.154682	2025-08-03 20:05:17.154682	0.39	4000.00
2397	\N	57	2025-04-10	11347.95	1	2025-08-03 20:05:17.384637	2025-08-03 20:05:17.384637	0.42	4709.97
2398	\N	57	2025-04-10	10353.11	1	2025-08-03 20:05:17.63313	2025-08-03 20:05:17.63313	0.50	5176.55
2399	\N	57	2025-04-10	13945.00	1	2025-08-03 20:05:17.86568	2025-08-03 20:05:17.86568	0.50	6972.50
2400	\N	57	2025-04-10	11269.17	1	2025-08-03 20:05:18.112811	2025-08-03 20:05:18.112811	0.55	6168.00
2401	\N	57	2025-04-10	5523.69	1	2025-08-03 20:05:18.376294	2025-08-03 20:05:18.376294	0.60	3314.21
2402	\N	57	2025-04-10	7974.25	1	2025-08-03 20:05:18.621545	2025-08-03 20:05:18.621545	0.40	3189.70
2403	\N	57	2025-04-10	15188.81	1	2025-08-03 20:05:18.974643	2025-08-03 20:05:18.974643	0.60	9109.48
2404	\N	57	2025-04-10	17909.74	1	2025-08-03 20:05:19.238219	2025-08-03 20:05:19.238219	0.60	10745.84
2405	\N	57	2025-04-10	6045.75	1	2025-08-03 20:05:19.48264	2025-08-03 20:05:19.48264	0.61	3714.95
2406	\N	88	2025-04-11	9886.96	1	2025-08-03 20:05:19.710519	2025-08-03 20:05:19.710519	0.40	3954.76
2407	\N	150	2025-04-11	6325.00	1	2025-08-03 20:05:19.928159	2025-08-03 20:05:19.928159	0.50	3162.50
2408	\N	80	2025-04-11	1630.00	1	2025-08-03 20:05:20.125765	2025-08-03 20:05:20.125765	0.80	1304.00
2409	\N	110	2025-04-11	7215.00	1	2025-08-03 20:05:20.551948	2025-08-03 20:05:20.551948	0.40	2886.00
2410	\N	57	2025-04-11	2863.13	1	2025-08-03 20:05:20.807242	2025-08-03 20:05:20.807242	0.25	715.78
2411	\N	57	2025-04-11	5805.00	1	2025-08-03 20:05:21.038567	2025-08-03 20:05:21.038567	0.17	1000.00
2412	\N	57	2025-04-11	12100.00	1	2025-08-03 20:05:21.26746	2025-08-03 20:05:21.26746	0.59	7100.00
2413	\N	44	2025-04-14	9234.17	1	2025-08-03 20:05:21.533707	2025-08-03 20:05:21.533707	0.50	4617.08
2414	\N	80	2025-04-14	15110.00	1	2025-08-03 20:05:21.786194	2025-08-03 20:05:21.786194	0.50	7555.00
2415	\N	116	2025-04-14	733.25	1	2025-08-03 20:05:22.031109	2025-08-03 20:05:22.031109	0.00	0.00
2416	\N	57	2025-04-14	12910.00	1	2025-08-03 20:05:22.318402	2025-08-03 20:05:22.318402	0.59	7670.00
2417	\N	60	2025-04-14	3965.00	1	2025-08-03 20:05:22.563464	2025-08-03 20:05:22.563464	0.50	1982.50
2418	\N	53	2025-04-14	7146.30	1	2025-08-03 20:05:22.820819	2025-08-03 20:05:22.820819	0.59	4200.00
2419	\N	53	2025-04-14	11950.83	1	2025-08-03 20:05:23.077372	2025-08-03 20:05:23.077372	0.57	6800.00
2420	\N	44	2025-04-15	5465.56	1	2025-08-03 20:05:23.257588	2025-08-03 20:05:23.257588	0.70	3825.90
2421	\N	44	2025-04-15	11810.65	1	2025-08-03 20:05:23.703779	2025-08-03 20:05:23.703779	0.49	5831.80
2422	\N	222	2025-04-15	7330.00	1	2025-08-03 20:05:24.169229	2025-08-03 20:05:24.169229	0.00	0.00
2423	\N	217	2025-04-15	12119.32	1	2025-08-03 20:05:24.399028	2025-08-03 20:05:24.399028	0.72	8722.07
2424	\N	217	2025-04-15	14611.03	1	2025-08-03 20:05:24.611195	2025-08-03 20:05:24.611195	0.50	7305.51
2425	\N	223	2025-04-15	4680.20	1	2025-08-03 20:05:24.985924	2025-08-03 20:05:24.985924	0.60	2808.12
2426	\N	224	2025-04-15	6785.00	1	2025-08-03 20:05:25.518053	2025-08-03 20:05:25.518053	0.50	3392.50
2427	\N	225	2025-04-15	10451.47	1	2025-08-03 20:05:26.004547	2025-08-03 20:05:26.004547	0.55	5748.31
2428	\N	48	2025-04-15	2877.24	1	2025-08-03 20:05:26.225268	2025-08-03 20:05:26.225268	0.65	1870.21
2429	\N	226	2025-04-15	6223.89	1	2025-08-03 20:05:26.612339	2025-08-03 20:05:26.612339	0.50	3111.95
2430	\N	110	2025-04-15	7440.00	1	2025-08-03 20:05:26.79718	2025-08-03 20:05:26.79718	0.65	4836.00
2431	\N	110	2025-04-15	3715.00	1	2025-08-03 20:05:26.987977	2025-08-03 20:05:26.987977	0.60	2229.00
2432	\N	57	2025-04-15	11430.01	1	2025-08-03 20:05:27.23157	2025-08-03 20:05:27.23157	0.34	3900.00
2433	\N	44	2025-04-16	14681.63	1	2025-08-03 20:05:27.474815	2025-08-03 20:05:27.474815	0.31	4560.54
2434	\N	45	2025-04-16	7500.00	1	2025-08-03 20:05:27.715356	2025-08-03 20:05:27.715356	0.50	3750.00
2435	\N	78	2025-04-16	12545.16	1	2025-08-03 20:05:28.066308	2025-08-03 20:05:28.066308	0.50	6272.58
2436	\N	48	2025-04-16	12292.75	1	2025-08-03 20:05:28.298097	2025-08-03 20:05:28.298097	0.57	7000.00
2437	\N	48	2025-04-16	9467.37	1	2025-08-03 20:05:28.534323	2025-08-03 20:05:28.534323	0.60	5680.42
2438	\N	55	2025-04-16	6120.00	1	2025-08-03 20:05:28.9809	2025-08-03 20:05:28.9809	0.50	3060.00
2439	\N	55	2025-04-16	6635.00	1	2025-08-03 20:05:29.235999	2025-08-03 20:05:29.235999	0.35	2322.25
2440	\N	55	2025-04-16	7700.00	1	2025-08-03 20:05:29.512577	2025-08-03 20:05:29.512577	0.45	3465.00
2441	\N	116	2025-04-16	9745.00	1	2025-08-03 20:05:29.705272	2025-08-03 20:05:29.705272	0.18	1752.04
2442	\N	57	2025-04-16	14785.21	1	2025-08-03 20:05:29.939638	2025-08-03 20:05:29.939638	0.50	7392.61
2443	\N	57	2025-04-16	700.00	1	2025-08-03 20:05:30.180332	2025-08-03 20:05:30.180332	0.64	450.00
2444	\N	57	2025-04-16	4040.00	1	2025-08-03 20:05:30.419703	2025-08-03 20:05:30.419703	0.45	1820.00
2445	\N	57	2025-04-16	10580.89	1	2025-08-03 20:05:30.641614	2025-08-03 20:05:30.641614	0.56	5917.63
2446	\N	57	2025-04-16	7165.10	1	2025-08-03 20:05:30.8884	2025-08-03 20:05:30.8884	0.55	3940.46
2447	\N	57	2025-04-16	10369.82	1	2025-08-03 20:05:31.073161	2025-08-03 20:05:31.073161	0.56	5760.98
2448	\N	160	2025-04-17	10745.00	1	2025-08-03 20:05:31.311386	2025-08-03 20:05:31.311386	0.55	5909.75
2449	\N	94	2025-04-17	9802.63	1	2025-08-03 20:05:31.541875	2025-08-03 20:05:31.541875	0.61	6000.00
2450	\N	94	2025-04-17	3543.92	1	2025-08-03 20:05:31.765118	2025-08-03 20:05:31.765118	0.56	2000.00
2451	\N	94	2025-04-17	4186.45	1	2025-08-03 20:05:31.998043	2025-08-03 20:05:31.998043	0.64	2700.00
2452	\N	94	2025-04-17	4470.75	1	2025-08-03 20:05:32.224708	2025-08-03 20:05:32.224708	0.67	3000.00
2453	\N	65	2025-04-17	11790.00	1	2025-08-03 20:05:32.403808	2025-08-03 20:05:32.403808	0.33	3918.34
2454	\N	136	2025-04-17	1125.00	1	2025-08-03 20:05:32.620333	2025-08-03 20:05:32.620333	0.55	618.75
2455	\N	57	2025-04-17	10609.00	1	2025-08-03 20:05:32.846197	2025-08-03 20:05:32.846197	0.60	6364.80
2456	\N	57	2025-04-17	700.00	1	2025-08-03 20:05:33.276731	2025-08-03 20:05:33.276731	0.50	350.00
2457	\N	44	2025-04-18	7896.63	1	2025-08-03 20:05:33.501719	2025-08-03 20:05:33.501719	0.40	3158.65
2458	\N	88	2025-04-18	7700.00	1	2025-08-03 20:05:33.727712	2025-08-03 20:05:33.727712	0.42	3234.00
2459	\N	80	2025-04-18	2501.60	1	2025-08-03 20:05:33.964751	2025-08-03 20:05:33.964751	0.65	1626.04
2460	\N	66	2025-04-18	11795.00	1	2025-08-03 20:05:34.204853	2025-08-03 20:05:34.204853	0.60	7077.00
2461	\N	55	2025-04-18	3880.00	1	2025-08-03 20:05:34.531224	2025-08-03 20:05:34.531224	0.50	1940.00
2462	\N	52	2025-04-18	9034.48	1	2025-08-03 20:05:34.75637	2025-08-03 20:05:34.75637	0.50	4518.00
2463	\N	57	2025-04-18	17745.00	1	2025-08-03 20:05:35.112508	2025-08-03 20:05:35.112508	0.50	8872.50
2464	\N	57	2025-04-18	15204.14	1	2025-08-03 20:05:35.295399	2025-08-03 20:05:35.295399	0.60	9121.00
2465	\N	60	2025-04-18	3735.00	1	2025-08-03 20:05:35.528911	2025-08-03 20:05:35.528911	0.75	2801.25
2466	\N	60	2025-04-18	10933.73	1	2025-08-03 20:05:35.762308	2025-08-03 20:05:35.762308	0.50	5466.87
2467	\N	44	2025-04-21	8960.00	1	2025-08-03 20:05:35.998983	2025-08-03 20:05:35.998983	0.59	5281.66
2468	\N	44	2025-04-21	8484.69	1	2025-08-03 20:05:36.225213	2025-08-03 20:05:36.225213	0.22	1906.66
2469	\N	44	2025-04-21	3032.15	1	2025-08-03 20:05:36.555986	2025-08-03 20:05:36.555986	0.60	1819.29
2470	\N	44	2025-04-21	914.15	1	2025-08-03 20:05:36.773314	2025-08-03 20:05:36.773314	0.50	457.06
2471	\N	44	2025-04-21	6811.70	1	2025-08-03 20:05:36.986839	2025-08-03 20:05:36.986839	0.54	3691.82
2472	\N	44	2025-04-21	11730.85	1	2025-08-03 20:05:37.213925	2025-08-03 20:05:37.213925	0.60	7038.51
2473	\N	227	2025-04-21	3235.00	1	2025-08-03 20:05:37.596832	2025-08-03 20:05:37.596832	0.51	1660.50
2474	\N	65	2025-04-21	7995.00	1	2025-08-03 20:05:37.764704	2025-08-03 20:05:37.764704	0.50	3997.50
2475	\N	122	2025-04-21	9082.33	1	2025-08-03 20:05:37.999189	2025-08-03 20:05:37.999189	0.40	3600.00
2476	\N	102	2025-04-21	2455.00	1	2025-08-03 20:05:38.221159	2025-08-03 20:05:38.221159	0.75	1841.25
2477	\N	57	2025-04-21	12210.00	1	2025-08-03 20:05:38.449961	2025-08-03 20:05:38.449961	0.49	6000.00
2478	\N	57	2025-04-21	19155.60	1	2025-08-03 20:05:38.677124	2025-08-03 20:05:38.677124	0.65	12451.14
2479	\N	60	2025-04-21	13575.33	1	2025-08-03 20:05:39.000004	2025-08-03 20:05:39.000004	0.50	6787.67
2480	\N	60	2025-04-21	10453.24	1	2025-08-03 20:05:39.221144	2025-08-03 20:05:39.221144	0.50	5226.62
2481	\N	44	2025-04-22	7447.52	1	2025-08-03 20:05:39.542544	2025-08-03 20:05:39.542544	0.38	2800.00
2482	\N	44	2025-04-22	9876.09	1	2025-08-03 20:05:39.771098	2025-08-03 20:05:39.771098	0.65	6419.46
2483	\N	45	2025-04-22	8420.00	1	2025-08-03 20:05:40.075233	2025-08-03 20:05:40.075233	0.50	4210.00
2484	\N	188	2025-04-22	15965.00	1	2025-08-03 20:05:40.255243	2025-08-03 20:05:40.255243	0.44	7000.00
2485	\N	94	2025-04-22	14182.03	1	2025-08-03 20:05:40.48425	2025-08-03 20:05:40.48425	0.67	9500.00
2486	\N	80	2025-04-22	8430.00	1	2025-08-03 20:05:40.651581	2025-08-03 20:05:40.651581	0.65	5479.50
2487	\N	80	2025-04-22	3941.96	1	2025-08-03 20:05:40.885889	2025-08-03 20:05:40.885889	0.65	2562.27
2488	\N	228	2025-04-22	5321.22	1	2025-08-03 20:05:41.525884	2025-08-03 20:05:41.525884	0.56	3000.00
2489	\N	66	2025-04-22	2055.00	1	2025-08-03 20:05:41.901343	2025-08-03 20:05:41.901343	0.49	1000.00
2490	\N	48	2025-04-22	6945.00	1	2025-08-03 20:05:42.176396	2025-08-03 20:05:42.176396	0.55	3800.00
2491	\N	48	2025-04-22	7185.00	1	2025-08-03 20:05:42.59073	2025-08-03 20:05:42.59073	0.58	4200.00
2492	\N	57	2025-04-22	13115.00	1	2025-08-03 20:05:42.838758	2025-08-03 20:05:42.838758	0.53	6965.00
2493	\N	57	2025-04-22	1773.50	1	2025-08-03 20:05:43.1192	2025-08-03 20:05:43.1192	0.55	975.42
2494	\N	57	2025-04-22	10180.00	1	2025-08-03 20:05:43.443738	2025-08-03 20:05:43.443738	0.55	5599.00
2495	\N	57	2025-04-22	14756.10	1	2025-08-03 20:05:43.689124	2025-08-03 20:05:43.689124	0.55	8115.85
2496	\N	57	2025-04-22	11706.75	1	2025-08-03 20:05:43.922455	2025-08-03 20:05:43.922455	0.60	7024.05
2497	\N	53	2025-04-22	6499.76	1	2025-08-03 20:05:44.15971	2025-08-03 20:05:44.15971	0.59	3850.00
2498	\N	53	2025-04-22	8881.64	1	2025-08-03 20:05:44.486168	2025-08-03 20:05:44.486168	0.51	4500.00
2499	\N	44	2025-04-23	14014.15	1	2025-08-03 20:05:44.680738	2025-08-03 20:05:44.680738	0.40	5605.66
2500	\N	44	2025-04-23	1680.00	1	2025-08-03 20:05:45.003323	2025-08-03 20:05:45.003323	0.50	840.00
2501	\N	44	2025-04-23	12467.47	1	2025-08-03 20:05:45.24429	2025-08-03 20:05:45.24429	0.40	4986.99
2502	\N	64	2025-04-23	4270.00	1	2025-08-03 20:05:45.482134	2025-08-03 20:05:45.482134	0.30	1281.00
2503	\N	48	2025-04-23	10133.50	1	2025-08-03 20:05:45.719568	2025-08-03 20:05:45.719568	0.59	6000.00
2504	\N	52	2025-04-23	7135.00	1	2025-08-03 20:05:45.955284	2025-08-03 20:05:45.955284	0.50	3567.50
2505	\N	52	2025-04-23	9486.45	1	2025-08-03 20:05:46.167761	2025-08-03 20:05:46.167761	0.50	4744.00
2506	\N	52	2025-04-23	11680.00	1	2025-08-03 20:05:46.418616	2025-08-03 20:05:46.418616	0.40	4672.00
2507	\N	52	2025-04-23	17885.00	1	2025-08-03 20:05:46.756945	2025-08-03 20:05:46.756945	0.40	7154.00
2508	\N	57	2025-04-23	18439.25	1	2025-08-03 20:05:46.997794	2025-08-03 20:05:46.997794	0.55	10141.59
2509	\N	57	2025-04-23	9661.87	1	2025-08-03 20:05:47.187828	2025-08-03 20:05:47.187828	0.55	5314.03
2510	\N	60	2025-04-23	6306.27	1	2025-08-03 20:05:47.437873	2025-08-03 20:05:47.437873	0.50	3153.14
2511	\N	73	2025-04-23	5373.45	1	2025-08-03 20:05:47.678505	2025-08-03 20:05:47.678505	0.26	1400.00
2512	\N	44	2025-04-24	5295.90	1	2025-08-03 20:05:47.922948	2025-08-03 20:05:47.922948	0.60	3166.66
2513	\N	44	2025-04-24	11418.04	1	2025-08-03 20:05:48.157188	2025-08-03 20:05:48.157188	0.57	6500.00
2514	\N	44	2025-04-24	645.00	1	2025-08-03 20:05:48.378524	2025-08-03 20:05:48.378524	0.60	387.00
2515	\N	44	2025-04-24	21770.83	1	2025-08-03 20:05:48.614705	2025-08-03 20:05:48.614705	0.37	8000.00
2516	\N	45	2025-04-24	2491.72	1	2025-08-03 20:05:48.803787	2025-08-03 20:05:48.803787	0.50	1245.86
2517	\N	219	2025-04-24	17028.70	1	2025-08-03 20:05:49.038185	2025-08-03 20:05:49.038185	0.50	8514.35
2518	\N	48	2025-04-24	10452.96	1	2025-08-03 20:05:49.283276	2025-08-03 20:05:49.283276	0.60	6271.78
2519	\N	57	2025-04-24	11705.00	1	2025-08-03 20:05:49.518594	2025-08-03 20:05:49.518594	0.10	1170.50
2520	\N	73	2025-04-24	8640.75	1	2025-08-03 20:05:49.744339	2025-08-03 20:05:49.744339	0.71	6125.00
2521	\N	45	2025-04-25	11450.32	1	2025-08-03 20:05:49.991882	2025-08-03 20:05:49.991882	0.52	6000.00
2522	\N	120	2025-04-25	2994.24	1	2025-08-03 20:05:50.181277	2025-08-03 20:05:50.181277	0.50	1497.12
2523	\N	229	2025-04-25	9734.23	1	2025-08-03 20:05:50.67942	2025-08-03 20:05:50.67942	0.65	6327.23
2524	\N	230	2025-04-25	5940.00	1	2025-08-03 20:05:51.038535	2025-08-03 20:05:51.038535	0.60	3564.00
2525	\N	51	2025-04-25	3080.02	1	2025-08-03 20:05:51.378715	2025-08-03 20:05:51.378715	0.50	1540.01
2526	\N	87	2025-04-25	4800.00	1	2025-08-03 20:05:51.749147	2025-08-03 20:05:51.749147	0.50	2400.00
2527	\N	52	2025-04-25	3105.85	1	2025-08-03 20:05:51.988696	2025-08-03 20:05:51.988696	0.50	1553.00
2528	\N	57	2025-04-25	12494.23	1	2025-08-03 20:05:52.538047	2025-08-03 20:05:52.538047	0.22	2796.25
2529	\N	57	2025-04-25	1005.00	1	2025-08-03 20:05:53.057692	2025-08-03 20:05:53.057692	0.65	653.25
2530	\N	57	2025-04-25	13385.00	1	2025-08-03 20:05:53.38221	2025-08-03 20:05:53.38221	0.30	4015.50
2531	\N	53	2025-04-25	4501.68	1	2025-08-03 20:05:53.633032	2025-08-03 20:05:53.633032	0.67	3000.00
2532	\N	44	2025-04-28	15707.01	1	2025-08-03 20:05:53.879239	2025-08-03 20:05:53.879239	0.51	7969.69
2533	\N	44	2025-04-28	2940.00	1	2025-08-03 20:05:54.252922	2025-08-03 20:05:54.252922	0.70	2058.00
2534	\N	44	2025-04-28	8616.74	1	2025-08-03 20:05:54.526031	2025-08-03 20:05:54.526031	0.70	6031.72
2535	\N	44	2025-04-28	4992.52	1	2025-08-03 20:05:54.785595	2025-08-03 20:05:54.785595	0.64	3196.66
2536	\N	127	2025-04-28	12014.21	1	2025-08-03 20:05:55.042781	2025-08-03 20:05:55.042781	0.50	6007.11
2537	\N	80	2025-04-28	7220.00	1	2025-08-03 20:05:55.295974	2025-08-03 20:05:55.295974	0.55	3971.00
2538	\N	80	2025-04-28	6185.00	1	2025-08-03 20:05:55.543982	2025-08-03 20:05:55.543982	0.45	2792.59
2539	\N	52	2025-04-28	4919.81	1	2025-08-03 20:05:55.796717	2025-08-03 20:05:55.796717	0.50	2460.00
2540	\N	57	2025-04-28	8885.00	1	2025-08-03 20:05:55.993254	2025-08-03 20:05:55.993254	0.36	3242.50
2541	\N	57	2025-04-28	12953.56	1	2025-08-03 20:05:56.2526	2025-08-03 20:05:56.2526	0.40	5181.42
2542	\N	57	2025-04-28	9216.18	1	2025-08-03 20:05:56.502056	2025-08-03 20:05:56.502056	0.59	5450.00
2543	\N	53	2025-04-28	10079.36	1	2025-08-03 20:05:56.748151	2025-08-03 20:05:56.748151	0.58	5800.00
2544	\N	53	2025-04-28	7278.33	1	2025-08-03 20:05:56.968451	2025-08-03 20:05:56.968451	0.41	3000.00
2545	\N	120	2025-04-29	6040.27	1	2025-08-03 20:05:57.240456	2025-08-03 20:05:57.240456	0.65	3926.18
2546	\N	231	2025-04-29	3785.00	1	2025-08-03 20:05:57.681166	2025-08-03 20:05:57.681166	0.50	1892.50
2547	\N	116	2025-04-29	9688.33	1	2025-08-03 20:05:57.899124	2025-08-03 20:05:57.899124	0.54	5231.68
2548	\N	116	2025-04-29	7890.00	1	2025-08-03 20:05:58.21613	2025-08-03 20:05:58.21613	0.65	5110.42
2549	\N	57	2025-04-29	12640.00	1	2025-08-03 20:05:58.606836	2025-08-03 20:05:58.606836	0.60	7584.00
2550	\N	57	2025-04-29	4330.00	1	2025-08-03 20:05:58.885405	2025-08-03 20:05:58.885405	0.50	2165.00
2551	\N	57	2025-04-29	9873.10	1	2025-08-03 20:05:59.15291	2025-08-03 20:05:59.15291	0.55	5400.00
2552	\N	57	2025-04-29	13575.25	1	2025-08-03 20:05:59.415079	2025-08-03 20:05:59.415079	0.43	5800.00
2553	\N	57	2025-04-29	4570.00	1	2025-08-03 20:05:59.694363	2025-08-03 20:05:59.694363	0.50	2285.00
2554	\N	57	2025-04-29	11570.00	1	2025-08-03 20:05:59.959903	2025-08-03 20:05:59.959903	0.58	6750.00
2555	\N	57	2025-04-29	5335.00	1	2025-08-03 20:06:00.237074	2025-08-03 20:06:00.237074	0.55	2910.00
2556	\N	57	2025-04-29	15027.78	1	2025-08-03 20:06:00.496176	2025-08-03 20:06:00.496176	0.58	8750.00
2557	\N	57	2025-04-29	15000.00	1	2025-08-03 20:06:00.76741	2025-08-03 20:06:00.76741	0.55	8250.00
2558	\N	57	2025-04-29	2421.57	1	2025-08-03 20:06:00.975101	2025-08-03 20:06:00.975101	0.52	1250.78
2559	\N	57	2025-04-29	11833.77	1	2025-08-03 20:06:01.285466	2025-08-03 20:06:01.285466	0.67	7892.00
2560	\N	57	2025-04-29	8687.36	1	2025-08-03 20:06:01.565181	2025-08-03 20:06:01.565181	0.57	4952.94
2561	\N	57	2025-04-29	3409.52	1	2025-08-03 20:06:01.845868	2025-08-03 20:06:01.845868	0.50	1704.75
2562	\N	44	2025-04-30	10164.70	1	2025-08-03 20:06:02.111593	2025-08-03 20:06:02.111593	0.42	4223.47
2563	\N	44	2025-04-30	10162.95	1	2025-08-03 20:06:02.386436	2025-08-03 20:06:02.386436	0.34	3480.66
2564	\N	45	2025-04-30	10257.26	1	2025-08-03 20:06:02.652213	2025-08-03 20:06:02.652213	0.50	5128.63
2565	\N	45	2025-04-30	10176.20	1	2025-08-03 20:06:03.01951	2025-08-03 20:06:03.01951	0.50	5088.10
2566	\N	211	2025-04-30	12160.00	1	2025-08-03 20:06:03.302215	2025-08-03 20:06:03.302215	0.65	7904.00
2567	\N	165	2025-04-30	12177.76	1	2025-08-03 20:06:03.556387	2025-08-03 20:06:03.556387	0.50	6088.88
2568	\N	120	2025-04-30	745.00	1	2025-08-03 20:06:03.79259	2025-08-03 20:06:03.79259	0.65	484.25
2569	\N	55	2025-04-30	8099.65	1	2025-08-03 20:06:04.029069	2025-08-03 20:06:04.029069	0.35	2834.88
2570	\N	55	2025-04-30	10297.51	1	2025-08-03 20:06:04.267518	2025-08-03 20:06:04.267518	0.50	5148.75
2571	\N	55	2025-04-30	8285.24	1	2025-08-03 20:06:04.575402	2025-08-03 20:06:04.575402	0.35	2899.83
2572	\N	102	2025-04-30	6103.06	1	2025-08-03 20:06:04.832193	2025-08-03 20:06:04.832193	0.50	3051.53
2573	\N	84	2025-04-30	3550.00	1	2025-08-03 20:06:05.115305	2025-08-03 20:06:05.115305	0.31	1100.00
2574	\N	84	2025-04-30	3740.00	1	2025-08-03 20:06:05.535095	2025-08-03 20:06:05.535095	0.29	1100.00
2575	\N	84	2025-04-30	3515.00	1	2025-08-03 20:06:05.903479	2025-08-03 20:06:05.903479	0.31	1100.00
2576	\N	84	2025-04-30	7400.00	1	2025-08-03 20:06:06.328331	2025-08-03 20:06:06.328331	0.66	4906.00
2577	\N	52	2025-04-30	8310.57	1	2025-08-03 20:06:06.652382	2025-08-03 20:06:06.652382	0.50	4155.00
2578	\N	57	2025-04-30	5939.27	1	2025-08-03 20:06:07.032643	2025-08-03 20:06:07.032643	0.51	3050.40
2579	\N	57	2025-04-30	16646.52	1	2025-08-03 20:06:07.306949	2025-08-03 20:06:07.306949	0.60	9905.00
2580	\N	57	2025-04-30	5925.00	1	2025-08-03 20:06:07.672198	2025-08-03 20:06:07.672198	0.15	904.08
2581	\N	57	2025-04-30	9310.00	1	2025-08-03 20:06:07.888574	2025-08-03 20:06:07.888574	0.57	5350.00
2582	\N	57	2025-04-30	11449.32	1	2025-08-03 20:06:08.241178	2025-08-03 20:06:08.241178	0.60	6840.00
2583	\N	53	2025-04-30	8030.31	1	2025-08-03 20:06:08.482782	2025-08-03 20:06:08.482782	0.40	3200.00
2584	\N	44	2025-05-01	8111.40	1	2025-08-03 20:06:08.719636	2025-08-03 20:06:08.719636	0.38	3097.33
2585	\N	44	2025-05-01	10110.88	1	2025-08-03 20:06:08.966306	2025-08-03 20:06:08.966306	0.39	3904.50
2586	\N	44	2025-05-01	7997.30	1	2025-08-03 20:06:09.192939	2025-08-03 20:06:09.192939	0.35	2794.00
2587	\N	44	2025-05-01	9216.60	1	2025-08-03 20:06:09.429283	2025-08-03 20:06:09.429283	0.31	2833.92
2588	\N	44	2025-05-01	3245.47	1	2025-08-03 20:06:09.67006	2025-08-03 20:06:09.67006	0.00	0.00
2589	\N	232	2025-05-01	3166.31	1	2025-08-03 20:06:10.210621	2025-08-03 20:06:10.210621	0.54	1700.00
2590	\N	233	2025-05-01	12850.00	1	2025-08-03 20:06:10.734815	2025-08-03 20:06:10.734815	0.60	7710.00
2591	\N	88	2025-05-01	8030.00	1	2025-08-03 20:06:10.94643	2025-08-03 20:06:10.94643	0.55	4416.50
2592	\N	66	2025-05-01	10625.00	1	2025-08-03 20:06:11.221442	2025-08-03 20:06:11.221442	0.50	5312.50
2593	\N	57	2025-05-01	720.40	1	2025-08-03 20:06:11.491582	2025-08-03 20:06:11.491582	0.46	330.00
2594	\N	57	2025-05-01	12703.60	1	2025-08-03 20:06:11.710603	2025-08-03 20:06:11.710603	0.61	7792.16
2595	\N	57	2025-05-01	12626.89	1	2025-08-03 20:06:11.891445	2025-08-03 20:06:11.891445	0.40	5050.75
2596	\N	53	2025-05-01	4255.00	1	2025-08-03 20:06:12.142359	2025-08-03 20:06:12.142359	0.75	3200.00
2597	\N	73	2025-05-01	9717.07	1	2025-08-03 20:06:12.381627	2025-08-03 20:06:12.381627	0.27	2625.00
2598	\N	44	2025-05-02	17916.18	1	2025-08-03 20:06:12.653891	2025-08-03 20:06:12.653891	0.26	4729.14
2599	\N	44	2025-05-02	12196.59	1	2025-08-03 20:06:12.852412	2025-08-03 20:06:12.852412	0.70	8537.62
2600	\N	234	2025-05-02	6850.80	1	2025-08-03 20:06:13.306935	2025-08-03 20:06:13.306935	0.50	3425.40
2601	\N	57	2025-05-02	6705.00	1	2025-08-03 20:06:13.638045	2025-08-03 20:06:13.638045	0.65	4325.51
2602	\N	57	2025-05-02	6930.21	1	2025-08-03 20:06:13.877076	2025-08-03 20:06:13.877076	0.54	3750.00
2603	\N	44	2025-05-05	15777.99	1	2025-08-03 20:06:14.078421	2025-08-03 20:06:14.078421	0.31	4891.16
2604	\N	44	2025-05-05	14731.35	1	2025-08-03 20:06:14.307249	2025-08-03 20:06:14.307249	0.37	5499.43
2605	\N	208	2025-05-05	10803.96	1	2025-08-03 20:06:14.548762	2025-08-03 20:06:14.548762	0.60	6482.38
2606	\N	57	2025-05-05	1559.65	1	2025-08-03 20:06:14.726324	2025-08-03 20:06:14.726324	0.50	779.82
2607	\N	57	2025-05-05	1559.65	1	2025-08-03 20:06:14.959721	2025-08-03 20:06:14.959721	0.50	779.82
2608	\N	44	2025-05-06	14162.33	1	2025-08-03 20:06:15.207559	2025-08-03 20:06:15.207559	0.39	5515.44
2609	\N	44	2025-05-06	8850.04	1	2025-08-03 20:06:15.422397	2025-08-03 20:06:15.422397	0.62	5487.00
2610	\N	44	2025-05-06	8591.20	1	2025-08-03 20:06:15.6562	2025-08-03 20:06:15.6562	0.29	2500.00
2611	\N	44	2025-05-06	5479.05	1	2025-08-03 20:06:15.88601	2025-08-03 20:06:15.88601	0.39	2159.50
2612	\N	44	2025-05-06	5620.41	1	2025-08-03 20:06:16.077025	2025-08-03 20:06:16.077025	0.50	2810.21
2613	\N	44	2025-05-06	4564.37	1	2025-08-03 20:06:16.352227	2025-08-03 20:06:16.352227	0.60	2738.63
2614	\N	44	2025-05-06	9462.52	1	2025-08-03 20:06:16.602075	2025-08-03 20:06:16.602075	0.70	6623.76
2615	\N	134	2025-05-06	7842.24	1	2025-08-03 20:06:16.9097	2025-08-03 20:06:16.9097	0.50	3921.12
2616	\N	134	2025-05-06	6975.00	1	2025-08-03 20:06:17.178593	2025-08-03 20:06:17.178593	0.60	4185.00
2617	\N	134	2025-05-06	7585.00	1	2025-08-03 20:06:17.468631	2025-08-03 20:06:17.468631	0.60	4551.00
2618	\N	65	2025-05-06	17350.65	1	2025-08-03 20:06:17.938476	2025-08-03 20:06:17.938476	0.29	5000.00
2619	\N	52	2025-05-06	12816.45	1	2025-08-03 20:06:18.157	2025-08-03 20:06:18.157	0.60	7690.00
2620	\N	57	2025-05-06	8486.85	1	2025-08-03 20:06:18.507399	2025-08-03 20:06:18.507399	0.55	4667.76
2621	\N	57	2025-05-06	11652.15	1	2025-08-03 20:06:18.806665	2025-08-03 20:06:18.806665	0.55	6408.62
2622	\N	57	2025-05-06	2705.00	1	2025-08-03 20:06:19.053579	2025-08-03 20:06:19.053579	0.57	1544.00
2623	\N	53	2025-05-06	3621.35	1	2025-08-03 20:06:19.303783	2025-08-03 20:06:19.303783	0.75	2700.00
2624	\N	53	2025-05-06	6383.08	1	2025-08-03 20:06:19.570555	2025-08-03 20:06:19.570555	0.78	5000.00
2625	\N	53	2025-05-06	9356.92	1	2025-08-03 20:06:19.814547	2025-08-03 20:06:19.814547	0.74	6900.00
2626	\N	73	2025-05-06	12565.68	1	2025-08-03 20:06:20.06884	2025-08-03 20:06:20.06884	0.39	4894.67
2627	\N	44	2025-05-07	9249.61	1	2025-08-03 20:06:20.434943	2025-08-03 20:06:20.434943	0.60	5549.76
2628	\N	44	2025-05-07	4960.00	1	2025-08-03 20:06:20.67691	2025-08-03 20:06:20.67691	0.60	2976.00
2629	\N	71	2025-05-07	710.00	1	2025-08-03 20:06:20.918086	2025-08-03 20:06:20.918086	0.55	390.50
2630	\N	80	2025-05-07	12697.76	1	2025-08-03 20:06:21.255937	2025-08-03 20:06:21.255937	0.50	6368.04
2631	\N	235	2025-05-07	930.00	1	2025-08-03 20:06:21.665457	2025-08-03 20:06:21.665457	0.50	465.00
2632	\N	230	2025-05-07	6345.00	1	2025-08-03 20:06:21.879183	2025-08-03 20:06:21.879183	0.50	3172.50
2633	\N	55	2025-05-07	5090.00	1	2025-08-03 20:06:22.130985	2025-08-03 20:06:22.130985	0.60	3054.00
2634	\N	55	2025-05-07	3905.00	1	2025-08-03 20:06:22.319808	2025-08-03 20:06:22.319808	0.60	2343.00
2635	\N	57	2025-05-07	11245.00	1	2025-08-03 20:06:22.56788	2025-08-03 20:06:22.56788	0.55	6184.75
2636	\N	57	2025-05-07	14750.00	1	2025-08-03 20:06:22.792322	2025-08-03 20:06:22.792322	0.50	7435.00
2637	\N	57	2025-05-07	11550.00	1	2025-08-03 20:06:23.665914	2025-08-03 20:06:23.665914	0.58	6725.00
2638	\N	57	2025-05-07	4470.00	1	2025-08-03 20:06:23.917421	2025-08-03 20:06:23.917421	0.70	3145.00
2639	\N	44	2025-05-08	6835.90	1	2025-08-03 20:06:24.151587	2025-08-03 20:06:24.151587	0.36	2431.30
2640	\N	44	2025-05-08	11079.50	1	2025-08-03 20:06:24.347088	2025-08-03 20:06:24.347088	0.47	5193.89
2641	\N	44	2025-05-08	17842.98	1	2025-08-03 20:06:24.547113	2025-08-03 20:06:24.547113	0.41	7300.80
2642	\N	44	2025-05-08	7055.00	1	2025-08-03 20:06:24.832627	2025-08-03 20:06:24.832627	0.60	4233.00
2643	\N	44	2025-05-08	13900.11	1	2025-08-03 20:06:25.157227	2025-08-03 20:06:25.157227	0.34	4719.76
2644	\N	44	2025-05-08	12732.25	1	2025-08-03 20:06:25.486344	2025-08-03 20:06:25.486344	0.41	5188.91
2645	\N	81	2025-05-08	14464.73	1	2025-08-03 20:06:25.70662	2025-08-03 20:06:25.70662	0.50	7232.36
2646	\N	134	2025-05-08	8231.92	1	2025-08-03 20:06:25.939525	2025-08-03 20:06:25.939525	0.50	4115.95
2647	\N	48	2025-05-08	6985.00	1	2025-08-03 20:06:26.179447	2025-08-03 20:06:26.179447	0.40	2800.00
2648	\N	52	2025-05-08	11139.70	1	2025-08-03 20:06:26.517104	2025-08-03 20:06:26.517104	0.50	5570.00
2649	\N	57	2025-05-08	5317.07	1	2025-08-03 20:06:26.756862	2025-08-03 20:06:26.756862	0.55	2924.39
2650	\N	57	2025-05-08	11088.95	1	2025-08-03 20:06:26.988645	2025-08-03 20:06:26.988645	0.60	6653.37
2651	\N	57	2025-05-08	12553.57	1	2025-08-03 20:06:27.216356	2025-08-03 20:06:27.216356	0.55	6920.00
2652	\N	53	2025-05-08	7633.69	1	2025-08-03 20:06:27.485862	2025-08-03 20:06:27.485862	0.65	5000.00
2653	\N	53	2025-05-08	9296.08	1	2025-08-03 20:06:27.730786	2025-08-03 20:06:27.730786	0.54	5000.00
2654	\N	44	2025-05-09	11518.25	1	2025-08-03 20:06:27.973056	2025-08-03 20:06:27.973056	0.60	6910.89
2655	\N	44	2025-05-09	6190.67	1	2025-08-03 20:06:28.331527	2025-08-03 20:06:28.331527	0.31	1932.33
2656	\N	71	2025-05-09	8177.37	1	2025-08-03 20:06:28.638861	2025-08-03 20:06:28.638861	0.40	3270.95
2657	\N	236	2025-05-09	10870.66	1	2025-08-03 20:06:29.115839	2025-08-03 20:06:29.115839	0.49	5300.00
2658	\N	55	2025-05-09	6449.92	1	2025-08-03 20:06:29.398395	2025-08-03 20:06:29.398395	0.50	3224.96
2659	\N	52	2025-05-09	8540.80	1	2025-08-03 20:06:29.679606	2025-08-03 20:06:29.679606	0.50	4271.00
2660	\N	52	2025-05-09	5051.76	1	2025-08-03 20:06:30.086811	2025-08-03 20:06:30.086811	0.60	3031.00
2661	\N	52	2025-05-09	6243.57	1	2025-08-03 20:06:30.405959	2025-08-03 20:06:30.405959	0.60	3746.00
2662	\N	52	2025-05-09	14143.94	1	2025-08-03 20:06:30.676464	2025-08-03 20:06:30.676464	0.44	6272.00
2663	\N	208	2025-05-09	10868.45	1	2025-08-03 20:06:30.959719	2025-08-03 20:06:30.959719	0.68	7400.00
2664	\N	57	2025-05-09	19866.07	1	2025-08-03 20:06:31.250479	2025-08-03 20:06:31.250479	0.58	11550.00
2665	\N	57	2025-05-09	8250.87	1	2025-08-03 20:06:31.577491	2025-08-03 20:06:31.577491	0.47	3900.00
2666	\N	57	2025-05-09	11565.00	1	2025-08-03 20:06:31.883718	2025-08-03 20:06:31.883718	0.58	6700.00
2667	\N	53	2025-05-09	8320.00	1	2025-08-03 20:06:32.158792	2025-08-03 20:06:32.158792	0.60	5000.00
2668	\N	43	2025-05-12	5865.00	1	2025-08-03 20:06:32.405119	2025-08-03 20:06:32.405119	0.50	2932.50
2669	\N	44	2025-05-12	11448.93	1	2025-08-03 20:06:32.651175	2025-08-03 20:06:32.651175	0.50	5724.46
2670	\N	44	2025-05-12	10197.91	1	2025-08-03 20:06:32.845418	2025-08-03 20:06:32.845418	0.29	3000.00
2671	\N	44	2025-05-12	5554.80	1	2025-08-03 20:06:33.268447	2025-08-03 20:06:33.268447	0.41	2267.61
2672	\N	237	2025-05-12	1900.00	1	2025-08-03 20:06:33.74924	2025-08-03 20:06:33.74924	0.60	1140.00
2673	\N	66	2025-05-12	3665.00	1	2025-08-03 20:06:34.057238	2025-08-03 20:06:34.057238	0.40	1466.00
2674	\N	148	2025-05-12	10910.00	1	2025-08-03 20:06:34.410156	2025-08-03 20:06:34.410156	0.50	5455.00
2675	\N	57	2025-05-12	11310.00	1	2025-08-03 20:06:34.643668	2025-08-03 20:06:34.643668	0.55	6220.50
2676	\N	57	2025-05-12	2100.00	1	2025-08-03 20:06:34.858546	2025-08-03 20:06:34.858546	0.73	1532.00
2677	\N	43	2025-05-13	5695.00	1	2025-08-03 20:06:35.091827	2025-08-03 20:06:35.091827	0.48	2745.00
2678	\N	44	2025-05-13	12819.50	1	2025-08-03 20:06:35.319847	2025-08-03 20:06:35.319847	0.31	3945.33
2679	\N	148	2025-05-13	11935.00	1	2025-08-03 20:06:35.559019	2025-08-03 20:06:35.559019	0.51	6135.83
2680	\N	102	2025-05-13	1530.00	1	2025-08-03 20:06:35.789429	2025-08-03 20:06:35.789429	0.75	1147.50
2681	\N	116	2025-05-13	3803.55	1	2025-08-03 20:06:36.145654	2025-08-03 20:06:36.145654	0.55	2091.68
2682	\N	116	2025-05-13	8905.00	1	2025-08-03 20:06:36.403109	2025-08-03 20:06:36.403109	0.31	2800.00
2683	\N	57	2025-05-13	16053.65	1	2025-08-03 20:06:36.780745	2025-08-03 20:06:36.780745	0.52	8316.32
2684	\N	57	2025-05-13	7106.27	1	2025-08-03 20:06:37.065201	2025-08-03 20:06:37.065201	0.60	4260.00
2685	\N	57	2025-05-13	3990.73	1	2025-08-03 20:06:37.32714	2025-08-03 20:06:37.32714	0.60	2390.00
2686	\N	57	2025-05-13	9782.55	1	2025-08-03 20:06:37.582985	2025-08-03 20:06:37.582985	0.50	4891.27
2687	\N	57	2025-05-13	1377.00	1	2025-08-03 20:06:37.821039	2025-08-03 20:06:37.821039	0.55	757.34
2688	\N	57	2025-05-13	7596.48	1	2025-08-03 20:06:38.07537	2025-08-03 20:06:38.07537	0.53	4027.42
2689	\N	57	2025-05-13	10997.31	1	2025-08-03 20:06:38.345218	2025-08-03 20:06:38.345218	0.20	2199.46
2690	\N	44	2025-05-14	11752.01	1	2025-08-03 20:06:38.601248	2025-08-03 20:06:38.601248	0.58	6850.98
2691	\N	44	2025-05-14	5277.60	1	2025-08-03 20:06:38.84733	2025-08-03 20:06:38.84733	0.33	1750.00
2692	\N	148	2025-05-14	5975.00	1	2025-08-03 20:06:39.093896	2025-08-03 20:06:39.093896	0.61	3617.75
2693	\N	52	2025-05-14	6503.71	1	2025-08-03 20:06:39.293372	2025-08-03 20:06:39.293372	0.50	3252.00
2694	\N	208	2025-05-14	11774.14	1	2025-08-03 20:06:39.541919	2025-08-03 20:06:39.541919	0.60	7053.19
2695	\N	57	2025-05-14	5010.00	1	2025-08-03 20:06:39.78907	2025-08-03 20:06:39.78907	0.56	2783.90
2696	\N	57	2025-05-14	4642.40	1	2025-08-03 20:06:40.067355	2025-08-03 20:06:40.067355	0.60	2785.00
2697	\N	60	2025-05-14	1785.00	1	2025-08-03 20:06:40.348763	2025-08-03 20:06:40.348763	0.65	1160.25
2698	\N	44	2025-05-15	6286.50	1	2025-08-03 20:06:40.604601	2025-08-03 20:06:40.604601	0.65	4086.23
2699	\N	44	2025-05-15	10530.80	1	2025-08-03 20:06:40.841491	2025-08-03 20:06:40.841491	0.48	5089.31
2700	\N	44	2025-05-15	4974.81	1	2025-08-03 20:06:41.073907	2025-08-03 20:06:41.073907	0.45	2227.36
2701	\N	66	2025-05-15	2640.00	1	2025-08-03 20:06:41.305538	2025-08-03 20:06:41.305538	0.33	880.00
2702	\N	67	2025-05-15	1706.05	1	2025-08-03 20:06:41.550709	2025-08-03 20:06:41.550709	0.94	1600.00
2703	\N	55	2025-05-15	5910.00	1	2025-08-03 20:06:41.88635	2025-08-03 20:06:41.88635	0.50	2955.00
2704	\N	84	2025-05-15	4871.50	1	2025-08-03 20:06:42.12106	2025-08-03 20:06:42.12106	0.12	607.67
2705	\N	57	2025-05-15	12789.45	1	2025-08-03 20:06:42.336746	2025-08-03 20:06:42.336746	0.20	2557.89
2706	\N	57	2025-05-15	8066.82	1	2025-08-03 20:06:42.577573	2025-08-03 20:06:42.577573	0.60	4833.05
2707	\N	57	2025-05-15	15650.00	1	2025-08-03 20:06:42.807098	2025-08-03 20:06:42.807098	0.50	7825.00
2708	\N	57	2025-05-15	13491.67	1	2025-08-03 20:06:43.024331	2025-08-03 20:06:43.024331	0.60	8095.00
2709	\N	44	2025-05-16	3199.80	1	2025-08-03 20:06:43.365141	2025-08-03 20:06:43.365141	0.60	1920.20
2710	\N	105	2025-05-16	1898.75	1	2025-08-03 20:06:43.562122	2025-08-03 20:06:43.562122	0.61	1150.00
2711	\N	64	2025-05-16	4698.35	1	2025-08-03 20:06:43.825247	2025-08-03 20:06:43.825247	0.39	1819.01
2712	\N	162	2025-05-16	6845.00	1	2025-08-03 20:06:44.063876	2025-08-03 20:06:44.063876	0.50	3422.50
2713	\N	55	2025-05-16	7540.00	1	2025-08-03 20:06:44.294769	2025-08-03 20:06:44.294769	0.60	4524.00
2714	\N	102	2025-05-16	9523.70	1	2025-08-03 20:06:44.542703	2025-08-03 20:06:44.542703	0.50	4761.85
2715	\N	52	2025-05-16	14748.90	1	2025-08-03 20:06:44.730648	2025-08-03 20:06:44.730648	0.50	7374.00
2716	\N	116	2025-05-16	3830.00	1	2025-08-03 20:06:45.031661	2025-08-03 20:06:45.031661	0.51	1953.30
2717	\N	57	2025-05-16	12007.56	1	2025-08-03 20:06:45.311639	2025-08-03 20:06:45.311639	0.59	7120.00
2718	\N	57	2025-05-16	11137.17	1	2025-08-03 20:06:45.573484	2025-08-03 20:06:45.573484	0.60	6682.30
2719	\N	57	2025-05-16	11015.00	1	2025-08-03 20:06:45.932536	2025-08-03 20:06:45.932536	0.60	6600.00
2720	\N	60	2025-05-16	7702.92	1	2025-08-03 20:06:46.124103	2025-08-03 20:06:46.124103	0.55	4236.61
2721	\N	53	2025-05-16	7365.00	1	2025-08-03 20:06:46.48191	2025-08-03 20:06:46.48191	0.58	4250.00
2722	\N	53	2025-05-16	11612.47	1	2025-08-03 20:06:46.721268	2025-08-03 20:06:46.721268	0.56	6500.00
2723	\N	53	2025-05-16	9050.00	1	2025-08-03 20:06:47.038888	2025-08-03 20:06:47.038888	0.55	5000.00
2724	\N	129	2025-05-16	9045.00	1	2025-08-03 20:06:47.376757	2025-08-03 20:06:47.376757	0.65	5879.25
2725	\N	44	2025-05-19	7094.40	1	2025-08-03 20:06:47.619295	2025-08-03 20:06:47.619295	0.60	4256.64
2726	\N	44	2025-05-19	2247.80	1	2025-08-03 20:06:47.99305	2025-08-03 20:06:47.99305	0.60	1348.68
2727	\N	44	2025-05-19	7529.85	1	2025-08-03 20:06:48.203732	2025-08-03 20:06:48.203732	0.50	3731.18
2728	\N	65	2025-05-19	2355.00	1	2025-08-03 20:06:48.457791	2025-08-03 20:06:48.457791	0.25	588.75
2729	\N	55	2025-05-19	5355.00	1	2025-08-03 20:06:48.834498	2025-08-03 20:06:48.834498	0.69	3680.41
2730	\N	55	2025-05-19	7411.56	1	2025-08-03 20:06:49.082851	2025-08-03 20:06:49.082851	0.60	4446.94
2731	\N	102	2025-05-19	8445.00	1	2025-08-03 20:06:49.350442	2025-08-03 20:06:49.350442	0.70	5911.50
2732	\N	110	2025-05-19	8533.50	1	2025-08-03 20:06:49.614451	2025-08-03 20:06:49.614451	0.70	5973.45
2733	\N	116	2025-05-19	5955.00	1	2025-08-03 20:06:49.860094	2025-08-03 20:06:49.860094	0.38	2262.90
2734	\N	116	2025-05-19	5940.00	1	2025-08-03 20:06:50.115481	2025-08-03 20:06:50.115481	0.51	3029.40
2735	\N	60	2025-05-19	9466.55	1	2025-08-03 20:06:50.398195	2025-08-03 20:06:50.398195	0.55	5206.60
2736	\N	44	2025-05-20	12936.99	1	2025-08-03 20:06:50.791702	2025-08-03 20:06:50.791702	0.51	6630.00
2737	\N	44	2025-05-20	11568.36	1	2025-08-03 20:06:51.062327	2025-08-03 20:06:51.062327	0.38	4356.12
2738	\N	44	2025-05-20	9744.10	1	2025-08-03 20:06:51.390537	2025-08-03 20:06:51.390537	0.60	5846.46
2739	\N	44	2025-05-20	6099.20	1	2025-08-03 20:06:51.595161	2025-08-03 20:06:51.595161	0.70	4269.44
2740	\N	44	2025-05-20	7061.80	1	2025-08-03 20:06:51.822045	2025-08-03 20:06:51.822045	0.60	4237.08
2741	\N	44	2025-05-20	7870.00	1	2025-08-03 20:06:52.176057	2025-08-03 20:06:52.176057	0.22	1758.50
2742	\N	44	2025-05-20	12435.24	1	2025-08-03 20:06:52.533089	2025-08-03 20:06:52.533089	0.24	3026.56
2743	\N	206	2025-05-20	11935.00	1	2025-08-03 20:06:52.747597	2025-08-03 20:06:52.747597	0.55	6564.25
2744	\N	66	2025-05-20	3370.00	1	2025-08-03 20:06:53.138692	2025-08-03 20:06:53.138692	0.60	2022.00
2745	\N	238	2025-05-20	13120.00	1	2025-08-03 20:06:53.634193	2025-08-03 20:06:53.634193	0.49	6455.75
2746	\N	102	2025-05-20	9325.00	1	2025-08-03 20:06:54.017524	2025-08-03 20:06:54.017524	0.70	6527.50
2747	\N	102	2025-05-20	4711.69	1	2025-08-03 20:06:54.228494	2025-08-03 20:06:54.228494	0.50	2355.85
2748	\N	57	2025-05-20	10615.00	1	2025-08-03 20:06:54.579147	2025-08-03 20:06:54.579147	0.30	3184.50
2749	\N	57	2025-05-20	12700.00	1	2025-08-03 20:06:54.827179	2025-08-03 20:06:54.827179	0.59	7540.00
2750	\N	129	2025-05-20	9045.00	1	2025-08-03 20:06:55.061238	2025-08-03 20:06:55.061238	0.65	5879.25
2751	\N	44	2025-05-21	7976.42	1	2025-08-03 20:06:55.295321	2025-08-03 20:06:55.295321	0.50	3988.21
2752	\N	79	2025-05-21	5730.00	1	2025-08-03 20:06:55.585447	2025-08-03 20:06:55.585447	0.60	3438.00
2753	\N	80	2025-05-21	8435.00	1	2025-08-03 20:06:56.039804	2025-08-03 20:06:56.039804	0.50	4217.50
2754	\N	57	2025-05-21	7925.00	1	2025-08-03 20:06:56.286607	2025-08-03 20:06:56.286607	0.32	2542.50
2755	\N	57	2025-05-21	5800.00	1	2025-08-03 20:06:56.518963	2025-08-03 20:06:56.518963	0.60	3480.00
2756	\N	174	2025-05-21	6141.80	1	2025-08-03 20:06:56.86817	2025-08-03 20:06:56.86817	0.52	3200.00
2757	\N	239	2025-05-21	13402.96	1	2025-08-03 20:06:57.230861	2025-08-03 20:06:57.230861	0.60	8041.20
2758	\N	44	2025-05-22	13463.31	1	2025-08-03 20:06:57.429024	2025-08-03 20:06:57.429024	0.53	7128.88
2759	\N	44	2025-05-22	5800.06	1	2025-08-03 20:06:57.665368	2025-08-03 20:06:57.665368	0.21	1242.77
2760	\N	44	2025-05-22	10898.45	1	2025-08-03 20:06:58.004413	2025-08-03 20:06:58.004413	0.70	7628.92
2761	\N	44	2025-05-22	6076.57	1	2025-08-03 20:06:58.243172	2025-08-03 20:06:58.243172	0.21	1301.77
2762	\N	44	2025-05-22	1760.00	1	2025-08-03 20:06:58.455776	2025-08-03 20:06:58.455776	0.60	1056.00
2763	\N	218	2025-05-22	1745.00	1	2025-08-03 20:06:58.722303	2025-08-03 20:06:58.722303	0.65	1134.25
2764	\N	102	2025-05-22	5270.00	1	2025-08-03 20:06:58.949083	2025-08-03 20:06:58.949083	0.70	3689.00
2765	\N	52	2025-05-22	10777.32	1	2025-08-03 20:06:59.238088	2025-08-03 20:06:59.238088	0.50	5389.00
2766	\N	44	2025-05-23	6205.67	1	2025-08-03 20:06:59.509719	2025-08-03 20:06:59.509719	0.60	3723.40
2767	\N	44	2025-05-23	7667.16	1	2025-08-03 20:06:59.771271	2025-08-03 20:06:59.771271	0.23	1742.33
2768	\N	44	2025-05-23	5933.35	1	2025-08-03 20:07:00.00873	2025-08-03 20:07:00.00873	0.26	1541.33
2769	\N	44	2025-05-23	8745.87	1	2025-08-03 20:07:00.257004	2025-08-03 20:07:00.257004	0.70	6122.10
2770	\N	127	2025-05-23	9095.51	1	2025-08-03 20:07:00.485584	2025-08-03 20:07:00.485584	0.40	3638.20
2771	\N	135	2025-05-23	4215.00	1	2025-08-03 20:07:00.736216	2025-08-03 20:07:00.736216	0.52	2200.00
2772	\N	88	2025-05-23	11570.00	1	2025-08-03 20:07:00.989621	2025-08-03 20:07:00.989621	0.54	6247.80
2773	\N	88	2025-05-23	10147.34	1	2025-08-03 20:07:01.188813	2025-08-03 20:07:01.188813	0.70	7103.14
2774	\N	162	2025-05-23	1560.00	1	2025-08-03 20:07:01.446803	2025-08-03 20:07:01.446803	0.58	900.00
2775	\N	48	2025-05-23	6581.36	1	2025-08-03 20:07:01.690221	2025-08-03 20:07:01.690221	0.64	4200.00
2776	\N	48	2025-05-23	8113.71	1	2025-08-03 20:07:01.967023	2025-08-03 20:07:01.967023	0.60	4868.23
2777	\N	131	2025-05-23	12513.01	1	2025-08-03 20:07:02.244701	2025-08-03 20:07:02.244701	0.60	7500.00
2778	\N	124	2025-05-23	4205.00	1	2025-08-03 20:07:02.433541	2025-08-03 20:07:02.433541	0.45	1892.25
2779	\N	57	2025-05-23	12607.80	1	2025-08-03 20:07:02.611296	2025-08-03 20:07:02.611296	0.50	6303.90
2780	\N	53	2025-05-23	10403.44	1	2025-08-03 20:07:02.851365	2025-08-03 20:07:02.851365	0.65	6750.00
2781	\N	73	2025-05-23	1328.00	1	2025-08-03 20:07:03.08924	2025-08-03 20:07:03.08924	0.60	800.00
2782	\N	43	2025-05-27	1780.00	1	2025-08-03 20:07:03.328555	2025-08-03 20:07:03.328555	0.67	1200.00
2783	\N	44	2025-05-27	2755.00	1	2025-08-03 20:07:03.517879	2025-08-03 20:07:03.517879	0.50	1377.50
2784	\N	44	2025-05-27	14214.15	1	2025-08-03 20:07:03.757841	2025-08-03 20:07:03.757841	0.44	6227.17
2785	\N	44	2025-05-27	7818.37	1	2025-08-03 20:07:03.996899	2025-08-03 20:07:03.996899	0.68	5329.66
2786	\N	45	2025-05-27	7213.76	1	2025-08-03 20:07:04.219024	2025-08-03 20:07:04.219024	0.50	3606.88
2787	\N	161	2025-05-27	700.00	1	2025-08-03 20:07:04.563814	2025-08-03 20:07:04.563814	0.50	350.00
2788	\N	80	2025-05-27	13628.54	1	2025-08-03 20:07:04.808208	2025-08-03 20:07:04.808208	0.55	7495.70
2789	\N	236	2025-05-27	8041.94	1	2025-08-03 20:07:05.138465	2025-08-03 20:07:05.138465	0.50	4000.00
2790	\N	48	2025-05-27	8515.00	1	2025-08-03 20:07:05.375927	2025-08-03 20:07:05.375927	0.47	4000.00
2791	\N	55	2025-05-27	8132.67	1	2025-08-03 20:07:05.721328	2025-08-03 20:07:05.721328	0.50	4066.34
2792	\N	57	2025-05-27	10110.00	1	2025-08-03 20:07:06.050643	2025-08-03 20:07:06.050643	0.50	5055.00
2793	\N	57	2025-05-27	11270.00	1	2025-08-03 20:07:06.296686	2025-08-03 20:07:06.296686	0.58	6540.00
2794	\N	44	2025-05-28	3319.75	1	2025-08-03 20:07:06.524384	2025-08-03 20:07:06.524384	0.60	1991.85
2795	\N	44	2025-05-28	2076.05	1	2025-08-03 20:07:06.88298	2025-08-03 20:07:06.88298	0.60	1245.63
2796	\N	44	2025-05-28	5704.17	1	2025-08-03 20:07:07.206087	2025-08-03 20:07:07.206087	0.55	3137.30
2797	\N	44	2025-05-28	9134.41	1	2025-08-03 20:07:07.427451	2025-08-03 20:07:07.427451	0.60	5480.64
2798	\N	44	2025-05-28	2165.00	1	2025-08-03 20:07:07.659173	2025-08-03 20:07:07.659173	0.60	1299.00
2799	\N	44	2025-05-28	12468.89	1	2025-08-03 20:07:07.877195	2025-08-03 20:07:07.877195	0.55	6850.98
2800	\N	44	2025-05-28	2170.00	1	2025-08-03 20:07:08.126986	2025-08-03 20:07:08.126986	0.55	1194.00
2801	\N	71	2025-05-28	3235.00	1	2025-08-03 20:07:08.385057	2025-08-03 20:07:08.385057	0.40	1294.00
2802	\N	103	2025-05-28	14211.37	1	2025-08-03 20:07:08.560416	2025-08-03 20:07:08.560416	0.60	8500.00
2803	\N	184	2025-05-28	5903.00	1	2025-08-03 20:07:08.792598	2025-08-03 20:07:08.792598	0.60	3541.80
2804	\N	161	2025-05-28	1120.45	1	2025-08-03 20:07:09.037054	2025-08-03 20:07:09.037054	0.45	500.00
2805	\N	237	2025-05-28	3458.34	1	2025-08-03 20:07:09.256052	2025-08-03 20:07:09.256052	0.50	1729.17
2806	\N	167	2025-05-28	10730.00	1	2025-08-03 20:07:09.503985	2025-08-03 20:07:09.503985	0.50	5365.00
2807	\N	49	2025-05-28	1817.79	1	2025-08-03 20:07:09.749728	2025-08-03 20:07:09.749728	0.50	910.00
2808	\N	57	2025-05-28	7509.25	1	2025-08-03 20:07:10.117237	2025-08-03 20:07:10.117237	0.56	4200.00
2809	\N	57	2025-05-28	13981.24	1	2025-08-03 20:07:10.361353	2025-08-03 20:07:10.361353	0.60	8388.74
2810	\N	53	2025-05-28	7594.32	1	2025-08-03 20:07:10.588643	2025-08-03 20:07:10.588643	0.51	3900.00
2811	\N	53	2025-05-28	7670.57	1	2025-08-03 20:07:10.814745	2025-08-03 20:07:10.814745	0.51	3900.00
2812	\N	53	2025-05-28	5177.53	1	2025-08-03 20:07:11.052784	2025-08-03 20:07:11.052784	0.00	0.00
2813	\N	73	2025-05-28	6069.00	1	2025-08-03 20:07:11.281988	2025-08-03 20:07:11.281988	0.50	3034.50
2814	\N	44	2025-05-29	5157.45	1	2025-08-03 20:07:11.529596	2025-08-03 20:07:11.529596	0.60	3094.47
2815	\N	44	2025-05-29	3975.35	1	2025-08-03 20:07:11.735261	2025-08-03 20:07:11.735261	0.60	2385.21
2816	\N	44	2025-05-29	6553.60	1	2025-08-03 20:07:11.96379	2025-08-03 20:07:11.96379	0.60	3932.16
2817	\N	44	2025-05-29	5283.76	1	2025-08-03 20:07:12.254269	2025-08-03 20:07:12.254269	0.40	2113.50
2818	\N	44	2025-05-29	12321.51	1	2025-08-03 20:07:12.510172	2025-08-03 20:07:12.510172	0.64	7881.73
2819	\N	175	2025-05-29	8660.00	1	2025-08-03 20:07:12.765434	2025-08-03 20:07:12.765434	0.35	3000.00
2820	\N	90	2025-05-29	13520.00	1	2025-08-03 20:07:13.000782	2025-08-03 20:07:13.000782	0.55	7436.00
2821	\N	128	2025-05-29	1380.00	1	2025-08-03 20:07:13.195895	2025-08-03 20:07:13.195895	0.60	828.00
2822	\N	57	2025-05-29	3869.85	1	2025-08-03 20:07:13.39052	2025-08-03 20:07:13.39052	0.60	2321.91
2823	\N	44	2025-05-30	12101.24	1	2025-08-03 20:07:13.608468	2025-08-03 20:07:13.608468	0.60	7260.75
2824	\N	44	2025-05-30	5684.85	1	2025-08-03 20:07:13.807879	2025-08-03 20:07:13.807879	0.60	3410.91
2825	\N	44	2025-05-30	17625.10	1	2025-08-03 20:07:14.060361	2025-08-03 20:07:14.060361	0.47	8250.00
2826	\N	45	2025-05-30	6575.96	1	2025-08-03 20:07:14.348733	2025-08-03 20:07:14.348733	0.00	0.00
2827	\N	88	2025-05-30	15073.63	1	2025-08-03 20:07:14.608063	2025-08-03 20:07:14.608063	0.50	7536.81
2828	\N	88	2025-05-30	10267.84	1	2025-08-03 20:07:14.840008	2025-08-03 20:07:14.840008	0.49	5031.24
2829	\N	66	2025-05-30	11860.00	1	2025-08-03 20:07:15.093306	2025-08-03 20:07:15.093306	0.51	6000.00
2830	\N	167	2025-05-30	11900.00	1	2025-08-03 20:07:15.316451	2025-08-03 20:07:15.316451	0.50	5950.00
2831	\N	48	2025-05-30	6795.00	1	2025-08-03 20:07:15.547032	2025-08-03 20:07:15.547032	0.59	4000.00
2832	\N	240	2025-05-30	10110.00	1	2025-08-03 20:07:15.970123	2025-08-03 20:07:15.970123	0.50	5055.00
2833	\N	240	2025-05-30	9990.00	1	2025-08-03 20:07:16.170709	2025-08-03 20:07:16.170709	0.50	4995.00
2834	\N	57	2025-05-30	8015.29	1	2025-08-03 20:07:16.41882	2025-08-03 20:07:16.41882	0.60	4800.00
2835	\N	44	2025-06-02	10943.74	1	2025-08-03 20:07:16.651383	2025-08-03 20:07:16.651383	0.60	6566.24
2836	\N	44	2025-06-02	4759.42	1	2025-08-03 20:07:16.87801	2025-08-03 20:07:16.87801	0.53	2508.48
2837	\N	44	2025-06-02	11882.26	1	2025-08-03 20:07:17.106952	2025-08-03 20:07:17.106952	0.55	6535.25
2838	\N	44	2025-06-02	7093.74	1	2025-08-03 20:07:17.359718	2025-08-03 20:07:17.359718	0.37	2617.25
2839	\N	44	2025-06-02	6352.95	1	2025-08-03 20:07:17.596754	2025-08-03 20:07:17.596754	0.50	3176.48
2840	\N	83	2025-06-02	5451.05	1	2025-08-03 20:07:17.832056	2025-08-03 20:07:17.832056	0.50	2725.50
2841	\N	231	2025-06-02	8115.00	1	2025-08-03 20:07:18.067044	2025-08-03 20:07:18.067044	0.60	4869.00
2842	\N	116	2025-06-02	10233.05	1	2025-08-03 20:07:18.241036	2025-08-03 20:07:18.241036	0.00	0.00
2843	\N	126	2025-06-02	10258.08	1	2025-08-03 20:07:18.473982	2025-08-03 20:07:18.473982	0.50	5100.00
2844	\N	57	2025-06-02	3745.82	1	2025-08-03 20:07:18.723355	2025-08-03 20:07:18.723355	0.60	2250.00
2845	\N	57	2025-06-02	8010.60	1	2025-08-03 20:07:18.941028	2025-08-03 20:07:18.941028	0.59	4700.00
2846	\N	57	2025-06-02	9808.48	1	2025-08-03 20:07:19.174929	2025-08-03 20:07:19.174929	0.60	5885.00
2847	\N	57	2025-06-02	9788.34	1	2025-08-03 20:07:19.41295	2025-08-03 20:07:19.41295	0.60	5873.00
2848	\N	57	2025-06-02	7020.50	1	2025-08-03 20:07:19.650537	2025-08-03 20:07:19.650537	0.60	4212.30
2849	\N	57	2025-06-02	4839.49	1	2025-08-03 20:07:19.897189	2025-08-03 20:07:19.897189	0.60	2915.00
2850	\N	60	2025-06-02	10989.63	1	2025-08-03 20:07:20.176832	2025-08-03 20:07:20.176832	0.70	7692.74
2851	\N	53	2025-06-02	8195.37	1	2025-08-03 20:07:20.518052	2025-08-03 20:07:20.518052	0.70	5700.00
2852	\N	44	2025-06-03	28158.92	1	2025-08-03 20:07:20.753181	2025-08-03 20:07:20.753181	0.28	7922.72
2853	\N	44	2025-06-03	838.95	1	2025-08-03 20:07:20.999379	2025-08-03 20:07:20.999379	0.70	587.27
2854	\N	44	2025-06-03	4799.80	1	2025-08-03 20:07:21.236525	2025-08-03 20:07:21.236525	0.42	2020.00
2855	\N	44	2025-06-03	13501.91	1	2025-08-03 20:07:21.577069	2025-08-03 20:07:21.577069	0.51	6853.60
2856	\N	44	2025-06-03	7244.55	1	2025-08-03 20:07:21.907103	2025-08-03 20:07:21.907103	0.55	3984.51
2857	\N	44	2025-06-03	11448.09	1	2025-08-03 20:07:22.148849	2025-08-03 20:07:22.148849	0.60	6868.85
2858	\N	48	2025-06-03	15010.97	1	2025-08-03 20:07:22.392956	2025-08-03 20:07:22.392956	0.57	8500.00
2859	\N	48	2025-06-03	12526.82	1	2025-08-03 20:07:22.643722	2025-08-03 20:07:22.643722	0.56	7000.00
2860	\N	48	2025-06-03	6109.65	1	2025-08-03 20:07:22.872907	2025-08-03 20:07:22.872907	0.64	3900.00
2861	\N	241	2025-06-03	10731.63	1	2025-08-03 20:07:23.277732	2025-08-03 20:07:23.277732	0.46	4980.00
2862	\N	57	2025-06-03	3670.34	1	2025-08-03 20:07:23.595706	2025-08-03 20:07:23.595706	0.60	2200.00
2863	\N	57	2025-06-03	728.85	1	2025-08-03 20:07:23.832557	2025-08-03 20:07:23.832557	0.60	440.38
2864	\N	57	2025-06-03	24195.00	1	2025-08-03 20:07:24.073839	2025-08-03 20:07:24.073839	0.52	12517.00
2865	\N	57	2025-06-03	12631.90	1	2025-08-03 20:07:24.275601	2025-08-03 20:07:24.275601	0.42	5300.00
2866	\N	57	2025-06-03	11730.00	1	2025-08-03 20:07:24.560141	2025-08-03 20:07:24.560141	0.15	1759.50
2867	\N	44	2025-06-04	11809.67	1	2025-08-03 20:07:24.803949	2025-08-03 20:07:24.803949	0.58	6849.61
2868	\N	242	2025-06-04	5860.00	1	2025-08-03 20:07:25.354716	2025-08-03 20:07:25.354716	0.17	1000.00
2869	\N	64	2025-06-04	8905.00	1	2025-08-03 20:07:25.559636	2025-08-03 20:07:25.559636	0.40	3562.00
2870	\N	48	2025-06-04	9264.41	1	2025-08-03 20:07:25.797441	2025-08-03 20:07:25.797441	0.60	5558.65
2871	\N	102	2025-06-04	6410.00	1	2025-08-03 20:07:26.126176	2025-08-03 20:07:26.126176	0.00	0.00
2872	\N	57	2025-06-04	8585.97	1	2025-08-03 20:07:26.365168	2025-08-03 20:07:26.365168	0.64	5493.37
2873	\N	53	2025-06-04	7283.24	1	2025-08-03 20:07:26.719706	2025-08-03 20:07:26.719706	0.74	5400.00
2874	\N	44	2025-06-05	17436.17	1	2025-08-03 20:07:26.957011	2025-08-03 20:07:26.957011	0.45	7874.03
2875	\N	44	2025-06-05	3860.45	1	2025-08-03 20:07:27.2335	2025-08-03 20:07:27.2335	0.60	2316.27
2876	\N	134	2025-06-05	5473.03	1	2025-08-03 20:07:27.502808	2025-08-03 20:07:27.502808	0.60	3283.82
2877	\N	93	2025-06-05	4843.95	1	2025-08-03 20:07:27.768087	2025-08-03 20:07:27.768087	0.62	3000.00
2878	\N	116	2025-06-05	6695.00	1	2025-08-03 20:07:28.078762	2025-08-03 20:07:28.078762	0.51	3414.45
2879	\N	57	2025-06-05	8676.54	1	2025-08-03 20:07:28.327843	2025-08-03 20:07:28.327843	0.40	3470.61
2880	\N	57	2025-06-05	9371.45	1	2025-08-03 20:07:28.564766	2025-08-03 20:07:28.564766	0.56	5254.04
2881	\N	57	2025-06-05	12419.63	1	2025-08-03 20:07:28.823191	2025-08-03 20:07:28.823191	0.59	7340.00
2882	\N	57	2025-06-05	11730.00	1	2025-08-03 20:07:29.093637	2025-08-03 20:07:29.093637	0.15	1759.50
2883	\N	57	2025-06-05	8792.95	1	2025-08-03 20:07:29.351729	2025-08-03 20:07:29.351729	0.64	5650.00
2884	\N	53	2025-06-05	450.00	1	2025-08-03 20:07:29.612758	2025-08-03 20:07:29.612758	0.67	300.00
2885	\N	44	2025-06-09	1680.00	1	2025-08-03 20:07:29.877645	2025-08-03 20:07:29.877645	0.70	1176.00
2886	\N	44	2025-06-09	7820.00	1	2025-08-03 20:07:30.140984	2025-08-03 20:07:30.140984	0.46	3628.66
2887	\N	44	2025-06-09	9665.09	1	2025-08-03 20:07:30.405864	2025-08-03 20:07:30.405864	0.50	4832.55
2888	\N	44	2025-06-09	10278.67	1	2025-08-03 20:07:30.662731	2025-08-03 20:07:30.662731	0.38	3906.83
2889	\N	44	2025-06-09	1910.45	1	2025-08-03 20:07:30.894167	2025-08-03 20:07:30.894167	0.60	1146.27
2890	\N	44	2025-06-09	6525.00	1	2025-08-03 20:07:31.075214	2025-08-03 20:07:31.075214	0.50	3262.50
2891	\N	94	2025-06-09	4470.75	1	2025-08-03 20:07:31.355351	2025-08-03 20:07:31.355351	0.65	2900.23
2892	\N	134	2025-06-09	5365.00	1	2025-08-03 20:07:31.584405	2025-08-03 20:07:31.584405	0.50	2682.50
2893	\N	77	2025-06-09	5260.00	1	2025-08-03 20:07:31.817328	2025-08-03 20:07:31.817328	0.50	2630.00
2894	\N	52	2025-06-09	4920.55	1	2025-08-03 20:07:32.05713	2025-08-03 20:07:32.05713	0.50	2460.00
2895	\N	52	2025-06-09	11838.75	1	2025-08-03 20:07:32.288359	2025-08-03 20:07:32.288359	0.50	5919.00
2896	\N	57	2025-06-09	11815.00	1	2025-08-03 20:07:32.535794	2025-08-03 20:07:32.535794	0.58	6800.00
2897	\N	57	2025-06-09	4219.45	1	2025-08-03 20:07:32.810637	2025-08-03 20:07:32.810637	0.59	2480.00
2898	\N	57	2025-06-09	11690.00	1	2025-08-03 20:07:33.079248	2025-08-03 20:07:33.079248	0.55	6429.45
2899	\N	53	2025-06-09	3723.60	1	2025-08-03 20:07:33.385057	2025-08-03 20:07:33.385057	0.67	2500.00
2900	\N	44	2025-06-10	13547.01	1	2025-08-03 20:07:33.672963	2025-08-03 20:07:33.672963	0.52	7044.45
2901	\N	44	2025-06-10	12788.67	1	2025-08-03 20:07:33.93109	2025-08-03 20:07:33.93109	0.49	6266.92
2902	\N	44	2025-06-10	29592.98	1	2025-08-03 20:07:34.334526	2025-08-03 20:07:34.334526	0.30	8951.86
2903	\N	135	2025-06-10	16179.24	1	2025-08-03 20:07:34.551533	2025-08-03 20:07:34.551533	0.50	8089.62
2904	\N	55	2025-06-10	1725.00	1	2025-08-03 20:07:34.778905	2025-08-03 20:07:34.778905	0.51	872.10
2905	\N	57	2025-06-10	2862.30	1	2025-08-03 20:07:35.041013	2025-08-03 20:07:35.041013	0.51	1450.00
2906	\N	57	2025-06-10	2725.00	1	2025-08-03 20:07:35.300719	2025-08-03 20:07:35.300719	0.73	2000.00
2907	\N	73	2025-06-10	680.00	1	2025-08-03 20:07:35.550609	2025-08-03 20:07:35.550609	0.74	500.00
2908	\N	80	2025-06-11	1345.00	1	2025-08-03 20:07:35.785325	2025-08-03 20:07:35.785325	0.56	750.00
2909	\N	66	2025-06-11	10755.10	1	2025-08-03 20:07:36.02474	2025-08-03 20:07:36.02474	0.55	5915.31
2910	\N	86	2025-06-11	3215.00	1	2025-08-03 20:07:36.288381	2025-08-03 20:07:36.288381	0.67	2154.05
2911	\N	131	2025-06-11	11966.81	1	2025-08-03 20:07:36.506571	2025-08-03 20:07:36.506571	0.75	8975.11
2912	\N	131	2025-06-11	14543.83	1	2025-08-03 20:07:36.830204	2025-08-03 20:07:36.830204	0.75	10907.87
2913	\N	154	2025-06-11	11935.00	1	2025-08-03 20:07:37.059714	2025-08-03 20:07:37.059714	0.50	5945.00
2914	\N	154	2025-06-11	9820.00	1	2025-08-03 20:07:37.27542	2025-08-03 20:07:37.27542	0.50	4910.00
2915	\N	154	2025-06-11	1840.00	1	2025-08-03 20:07:37.491448	2025-08-03 20:07:37.491448	0.50	920.00
2916	\N	154	2025-06-11	2210.00	1	2025-08-03 20:07:37.718235	2025-08-03 20:07:37.718235	0.50	1105.00
2917	\N	124	2025-06-11	4730.00	1	2025-08-03 20:07:37.907884	2025-08-03 20:07:37.907884	0.35	1655.50
2918	\N	124	2025-06-11	4860.00	1	2025-08-03 20:07:38.22711	2025-08-03 20:07:38.22711	0.35	1701.00
2919	\N	55	2025-06-11	2829.30	1	2025-08-03 20:07:38.456334	2025-08-03 20:07:38.456334	0.50	1414.65
2920	\N	55	2025-06-11	2698.50	1	2025-08-03 20:07:38.67663	2025-08-03 20:07:38.67663	0.50	1349.25
2921	\N	243	2025-06-11	4811.80	1	2025-08-03 20:07:39.153205	2025-08-03 20:07:39.153205	0.60	2887.08
2922	\N	240	2025-06-11	10780.00	1	2025-08-03 20:07:39.383871	2025-08-03 20:07:39.383871	0.50	5390.00
2923	\N	52	2025-06-11	3371.69	1	2025-08-03 20:07:39.656059	2025-08-03 20:07:39.656059	0.50	1687.00
2924	\N	57	2025-06-11	13448.59	1	2025-08-03 20:07:39.922902	2025-08-03 20:07:39.922902	0.56	7484.22
2925	\N	57	2025-06-11	10430.91	1	2025-08-03 20:07:40.190426	2025-08-03 20:07:40.190426	0.57	5900.00
2926	\N	44	2025-06-12	3814.22	1	2025-08-03 20:07:40.435436	2025-08-03 20:07:40.435436	0.50	1907.11
2927	\N	44	2025-06-12	19083.27	1	2025-08-03 20:07:40.671822	2025-08-03 20:07:40.671822	0.37	6989.93
2928	\N	44	2025-06-12	16486.47	1	2025-08-03 20:07:40.949944	2025-08-03 20:07:40.949944	0.36	5960.14
2929	\N	44	2025-06-12	9310.21	1	2025-08-03 20:07:41.203708	2025-08-03 20:07:41.203708	0.69	6438.13
2930	\N	44	2025-06-12	6419.56	1	2025-08-03 20:07:41.479747	2025-08-03 20:07:41.479747	0.59	3759.33
2931	\N	80	2025-06-12	7177.27	1	2025-08-03 20:07:41.723476	2025-08-03 20:07:41.723476	0.60	4306.36
2932	47	80	2025-06-12	20901.89	1	2025-08-03 20:07:42.213505	2025-08-03 20:07:42.213505	0.45	9405.85
2933	\N	64	2025-06-12	14130.28	1	2025-08-03 20:07:42.502416	2025-08-03 20:07:42.502416	0.60	8478.00
2934	\N	64	2025-06-12	16227.52	1	2025-08-03 20:07:42.772407	2025-08-03 20:07:42.772407	0.50	8113.50
2935	\N	134	2025-06-12	6755.00	1	2025-08-03 20:07:43.029376	2025-08-03 20:07:43.029376	0.50	3377.50
2936	\N	84	2025-06-12	7160.00	1	2025-08-03 20:07:43.332351	2025-08-03 20:07:43.332351	0.83	5975.00
2937	\N	52	2025-06-12	12185.42	1	2025-08-03 20:07:43.575529	2025-08-03 20:07:43.575529	0.50	6093.00
2938	\N	57	2025-06-12	1673.90	1	2025-08-03 20:07:43.855214	2025-08-03 20:07:43.855214	0.60	1000.00
2939	\N	57	2025-06-12	9889.11	1	2025-08-03 20:07:44.133476	2025-08-03 20:07:44.133476	0.59	5800.00
2940	\N	57	2025-06-12	10519.37	1	2025-08-03 20:07:44.366702	2025-08-03 20:07:44.366702	0.61	6400.00
2941	\N	60	2025-06-12	5780.00	1	2025-08-03 20:07:44.708912	2025-08-03 20:07:44.708912	0.50	2890.00
2942	\N	44	2025-06-13	1120.45	1	2025-08-03 20:07:44.991874	2025-08-03 20:07:44.991874	0.60	672.27
2943	\N	44	2025-06-13	5959.49	1	2025-08-03 20:07:45.267576	2025-08-03 20:07:45.267576	0.60	3575.69
2944	\N	218	2025-06-13	9235.00	1	2025-08-03 20:07:45.558454	2025-08-03 20:07:45.558454	0.50	4617.50
2945	\N	218	2025-06-13	9185.00	1	2025-08-03 20:07:45.814539	2025-08-03 20:07:45.814539	0.50	4592.50
2946	\N	94	2025-06-13	7893.98	1	2025-08-03 20:07:46.061349	2025-08-03 20:07:46.061349	0.66	5200.00
2947	\N	55	2025-06-13	3785.00	1	2025-08-03 20:07:46.40707	2025-08-03 20:07:46.40707	0.50	1892.50
2948	\N	57	2025-06-13	20081.68	1	2025-08-03 20:07:46.638153	2025-08-03 20:07:46.638153	0.51	10340.74
2949	\N	66	2025-06-16	11725.00	1	2025-08-03 20:07:46.868367	2025-08-03 20:07:46.868367	0.55	6448.75
2950	\N	131	2025-06-16	4905.00	1	2025-08-03 20:07:47.115329	2025-08-03 20:07:47.115329	0.60	2943.00
2951	\N	55	2025-06-16	2897.69	1	2025-08-03 20:07:47.365872	2025-08-03 20:07:47.365872	0.50	1448.85
2952	\N	102	2025-06-16	9723.20	1	2025-08-03 20:07:47.601434	2025-08-03 20:07:47.601434	0.55	5347.76
2953	\N	84	2025-06-16	8945.00	1	2025-08-03 20:07:47.836057	2025-08-03 20:07:47.836057	0.75	6750.00
2954	\N	84	2025-06-16	6868.53	1	2025-08-03 20:07:48.181201	2025-08-03 20:07:48.181201	0.23	1600.00
2955	\N	84	2025-06-16	2261.45	1	2025-08-03 20:07:48.424613	2025-08-03 20:07:48.424613	0.31	700.00
2956	\N	84	2025-06-16	2751.17	1	2025-08-03 20:07:48.749681	2025-08-03 20:07:48.749681	0.25	700.00
2957	\N	116	2025-06-16	3891.03	1	2025-08-03 20:07:48.975636	2025-08-03 20:07:48.975636	0.54	2094.18
2958	\N	116	2025-06-16	5550.00	1	2025-08-03 20:07:49.207307	2025-08-03 20:07:49.207307	0.53	2929.27
2959	\N	57	2025-06-16	1125.00	1	2025-08-03 20:07:49.436508	2025-08-03 20:07:49.436508	0.55	618.75
2960	\N	57	2025-06-16	1679.32	1	2025-08-03 20:07:49.666767	2025-08-03 20:07:49.666767	0.60	1008.95
2961	\N	44	2025-06-17	16689.72	1	2025-08-03 20:07:49.890514	2025-08-03 20:07:49.890514	0.47	7866.15
2962	\N	44	2025-06-17	6551.33	1	2025-08-03 20:07:50.141001	2025-08-03 20:07:50.141001	0.26	1675.68
2963	\N	244	2025-06-17	2355.35	1	2025-08-03 20:07:50.554667	2025-08-03 20:07:50.554667	0.50	1177.68
2964	\N	88	2025-06-17	7555.00	1	2025-08-03 20:07:50.744444	2025-08-03 20:07:50.744444	0.15	1133.25
2965	\N	94	2025-06-17	9274.36	1	2025-08-03 20:07:50.983694	2025-08-03 20:07:50.983694	0.70	6500.00
2966	\N	116	2025-06-17	9172.43	1	2025-08-03 20:07:51.223798	2025-08-03 20:07:51.223798	0.50	4586.17
2967	\N	57	2025-06-17	8235.00	1	2025-08-03 20:07:51.457546	2025-08-03 20:07:51.457546	0.30	2470.50
2968	\N	57	2025-06-17	2369.13	1	2025-08-03 20:07:51.685999	2025-08-03 20:07:51.685999	0.60	1420.00
2969	\N	57	2025-06-17	9660.00	1	2025-08-03 20:07:51.912602	2025-08-03 20:07:51.912602	0.34	3272.69
2970	\N	73	2025-06-17	1903.00	1	2025-08-03 20:07:52.085477	2025-08-03 20:07:52.085477	0.79	1500.00
2971	\N	44	2025-06-18	8275.96	1	2025-08-03 20:07:52.31365	2025-08-03 20:07:52.31365	0.46	3799.13
2972	\N	44	2025-06-18	1120.45	1	2025-08-03 20:07:52.623905	2025-08-03 20:07:52.623905	0.60	672.27
2973	\N	44	2025-06-18	3163.29	1	2025-08-03 20:07:52.841136	2025-08-03 20:07:52.841136	0.70	2214.30
2974	\N	44	2025-06-18	4403.25	1	2025-08-03 20:07:53.059205	2025-08-03 20:07:53.059205	0.65	2873.33
2975	\N	44	2025-06-18	9130.00	1	2025-08-03 20:07:53.276119	2025-08-03 20:07:53.276119	0.40	3668.00
2976	\N	45	2025-06-18	6852.49	1	2025-08-03 20:07:53.50274	2025-08-03 20:07:53.50274	0.50	3426.25
2977	\N	74	2025-06-18	11503.00	1	2025-08-03 20:07:53.779253	2025-08-03 20:07:53.779253	0.70	8052.10
2978	\N	126	2025-06-18	9025.76	1	2025-08-03 20:07:54.007739	2025-08-03 20:07:54.007739	0.60	5400.00
2979	\N	126	2025-06-18	8944.80	1	2025-08-03 20:07:54.225979	2025-08-03 20:07:54.225979	0.60	5350.00
2980	\N	57	2025-06-18	22586.00	1	2025-08-03 20:07:54.454246	2025-08-03 20:07:54.454246	0.58	13210.00
2981	\N	57	2025-06-18	18775.97	1	2025-08-03 20:07:54.622972	2025-08-03 20:07:54.622972	0.58	10950.00
2982	\N	57	2025-06-18	7066.50	1	2025-08-03 20:07:54.851281	2025-08-03 20:07:54.851281	0.59	4150.00
2983	\N	57	2025-06-18	6255.00	1	2025-08-03 20:07:55.054803	2025-08-03 20:07:55.054803	0.34	2121.70
2984	\N	60	2025-06-18	4816.10	1	2025-08-03 20:07:55.277376	2025-08-03 20:07:55.277376	0.50	2408.05
2985	\N	53	2025-06-18	6717.87	1	2025-08-03 20:07:55.502218	2025-08-03 20:07:55.502218	0.68	4600.00
2986	\N	44	2025-06-19	6716.45	1	2025-08-03 20:07:55.751136	2025-08-03 20:07:55.751136	0.49	3318.81
2987	\N	44	2025-06-19	11713.74	1	2025-08-03 20:07:55.987312	2025-08-03 20:07:55.987312	0.34	3997.40
2988	\N	44	2025-06-19	17984.75	1	2025-08-03 20:07:56.248888	2025-08-03 20:07:56.248888	0.45	8181.85
2989	\N	44	2025-06-19	17153.25	1	2025-08-03 20:07:56.545522	2025-08-03 20:07:56.545522	0.48	8187.40
2990	\N	44	2025-06-19	3850.00	1	2025-08-03 20:07:56.788685	2025-08-03 20:07:56.788685	0.50	1925.00
2991	\N	175	2025-06-19	6662.62	1	2025-08-03 20:07:56.982619	2025-08-03 20:07:56.982619	0.60	3997.57
2992	\N	65	2025-06-19	7150.00	1	2025-08-03 20:07:57.22022	2025-08-03 20:07:57.22022	0.60	4290.00
2993	\N	117	2025-06-19	7606.45	1	2025-08-03 20:07:57.389344	2025-08-03 20:07:57.389344	0.50	3803.23
2994	\N	48	2025-06-19	10466.22	1	2025-08-03 20:07:57.616995	2025-08-03 20:07:57.616995	0.59	6200.00
2995	\N	48	2025-06-19	11105.97	1	2025-08-03 20:07:57.93156	2025-08-03 20:07:57.93156	0.59	6600.00
2996	\N	55	2025-06-19	2770.00	1	2025-08-03 20:07:58.254813	2025-08-03 20:07:58.254813	0.60	1662.00
2997	\N	55	2025-06-19	3851.28	1	2025-08-03 20:07:58.503125	2025-08-03 20:07:58.503125	0.60	2310.77
2998	\N	55	2025-06-19	7099.02	1	2025-08-03 20:07:58.687485	2025-08-03 20:07:58.687485	0.60	4259.41
2999	\N	55	2025-06-19	7557.62	1	2025-08-03 20:07:58.925062	2025-08-03 20:07:58.925062	0.50	3778.81
3000	\N	102	2025-06-19	2984.81	1	2025-08-03 20:07:59.189434	2025-08-03 20:07:59.189434	0.00	0.00
3001	\N	84	2025-06-19	9497.79	1	2025-08-03 20:07:59.389221	2025-08-03 20:07:59.389221	0.77	7286.25
3002	\N	84	2025-06-19	6210.00	1	2025-08-03 20:07:59.56467	2025-08-03 20:07:59.56467	0.41	2531.80
3003	\N	53	2025-06-19	7650.49	1	2025-08-03 20:07:59.764383	2025-08-03 20:07:59.764383	0.50	3825.00
3004	\N	44	2025-06-20	16663.79	1	2025-08-03 20:08:00.003482	2025-08-03 20:08:00.003482	0.48	7921.00
3005	\N	44	2025-06-20	3224.95	1	2025-08-03 20:08:00.279925	2025-08-03 20:08:00.279925	0.60	1934.97
3006	\N	44	2025-06-20	14146.96	1	2025-08-03 20:08:00.571257	2025-08-03 20:08:00.571257	0.36	5153.72
3007	\N	44	2025-06-20	7890.00	1	2025-08-03 20:08:00.918501	2025-08-03 20:08:00.918501	0.39	3082.25
3008	\N	44	2025-06-20	700.00	1	2025-08-03 20:08:01.223481	2025-08-03 20:08:01.223481	0.60	420.00
3009	\N	79	2025-06-20	7368.23	1	2025-08-03 20:08:01.529034	2025-08-03 20:08:01.529034	0.50	3684.12
3010	\N	88	2025-06-20	5723.97	1	2025-08-03 20:08:01.754225	2025-08-03 20:08:01.754225	0.50	2861.99
3011	\N	88	2025-06-20	9567.12	1	2025-08-03 20:08:02.0082	2025-08-03 20:08:02.0082	0.35	3348.49
3012	\N	88	2025-06-20	9936.92	1	2025-08-03 20:08:02.237564	2025-08-03 20:08:02.237564	0.40	4000.00
3013	\N	94	2025-06-20	14344.23	1	2025-08-03 20:08:02.411018	2025-08-03 20:08:02.411018	0.50	7172.12
3014	\N	131	2025-06-20	2332.72	1	2025-08-03 20:08:02.646955	2025-08-03 20:08:02.646955	0.60	1399.63
3015	\N	55	2025-06-20	7216.69	1	2025-08-03 20:08:02.875811	2025-08-03 20:08:02.875811	0.52	3763.25
3016	\N	57	2025-06-20	11395.00	1	2025-08-03 20:08:03.107774	2025-08-03 20:08:03.107774	0.62	7010.00
3017	\N	245	2025-06-20	16510.00	1	2025-08-03 20:08:03.529029	2025-08-03 20:08:03.529029	0.50	8255.00
3018	\N	44	2025-06-23	4154.55	1	2025-08-03 20:08:03.873541	2025-08-03 20:08:03.873541	0.25	1039.05
3019	\N	44	2025-06-23	700.00	1	2025-08-03 20:08:04.26053	2025-08-03 20:08:04.26053	0.60	420.00
3020	\N	44	2025-06-23	9575.92	1	2025-08-03 20:08:04.54918	2025-08-03 20:08:04.54918	0.70	6703.14
3021	\N	44	2025-06-23	1297.20	1	2025-08-03 20:08:04.801107	2025-08-03 20:08:04.801107	0.59	765.66
3022	\N	44	2025-06-23	5790.73	1	2025-08-03 20:08:05.045079	2025-08-03 20:08:05.045079	0.57	3322.07
3023	\N	217	2025-06-23	4403.30	1	2025-08-03 20:08:05.299174	2025-08-03 20:08:05.299174	0.68	3000.00
3024	\N	114	2025-06-23	7601.93	1	2025-08-03 20:08:05.559073	2025-08-03 20:08:05.559073	0.65	4941.24
3025	\N	66	2025-06-23	7117.51	1	2025-08-03 20:08:05.818119	2025-08-03 20:08:05.818119	0.49	3500.00
3026	\N	55	2025-06-23	2685.20	1	2025-08-03 20:08:06.04022	2025-08-03 20:08:06.04022	0.60	1611.00
3027	\N	57	2025-06-23	9290.00	1	2025-08-03 20:08:06.280975	2025-08-03 20:08:06.280975	0.30	2787.00
3028	\N	73	2025-06-23	17780.99	1	2025-08-03 20:08:06.495263	2025-08-03 20:08:06.495263	0.55	9750.00
3029	\N	44	2025-06-24	6115.56	1	2025-08-03 20:08:06.749432	2025-08-03 20:08:06.749432	0.50	3076.25
3030	\N	44	2025-06-24	8819.61	1	2025-08-03 20:08:07.033702	2025-08-03 20:08:07.033702	0.40	3537.20
3031	\N	44	2025-06-24	33264.10	1	2025-08-03 20:08:07.364508	2025-08-03 20:08:07.364508	0.19	6390.78
3032	\N	44	2025-06-24	6680.25	1	2025-08-03 20:08:07.621643	2025-08-03 20:08:07.621643	0.81	5435.29
3033	\N	44	2025-06-24	9370.30	1	2025-08-03 20:08:07.864759	2025-08-03 20:08:07.864759	0.18	1650.51
3034	\N	44	2025-06-24	9953.49	1	2025-08-03 20:08:08.056885	2025-08-03 20:08:08.056885	0.68	6762.00
3035	\N	44	2025-06-24	9906.94	1	2025-08-03 20:08:08.306587	2025-08-03 20:08:08.306587	0.30	3000.00
3036	\N	205	2025-06-24	13978.95	1	2025-08-03 20:08:08.556872	2025-08-03 20:08:08.556872	0.60	8386.80
3037	\N	246	2025-06-24	4780.18	1	2025-08-03 20:08:08.923308	2025-08-03 20:08:08.923308	0.65	3107.12
3038	\N	246	2025-06-24	8784.75	1	2025-08-03 20:08:09.127819	2025-08-03 20:08:09.127819	0.50	4392.38
3039	\N	114	2025-06-24	5220.80	1	2025-08-03 20:08:09.330855	2025-08-03 20:08:09.330855	0.65	3393.52
3040	\N	114	2025-06-24	5505.24	1	2025-08-03 20:08:09.569294	2025-08-03 20:08:09.569294	0.65	3578.41
3041	\N	55	2025-06-24	3130.00	1	2025-08-03 20:08:09.826629	2025-08-03 20:08:09.826629	0.50	1565.00
3042	\N	102	2025-06-24	1668.05	1	2025-08-03 20:08:10.102265	2025-08-03 20:08:10.102265	0.00	0.00
3043	\N	52	2025-06-24	6742.65	1	2025-08-03 20:08:10.352908	2025-08-03 20:08:10.352908	0.50	3372.00
3044	\N	116	2025-06-24	12009.52	1	2025-08-03 20:08:10.576773	2025-08-03 20:08:10.576773	0.52	6283.60
3045	\N	57	2025-06-24	2927.19	1	2025-08-03 20:08:10.809296	2025-08-03 20:08:10.809296	0.40	1170.87
3046	\N	57	2025-06-24	9980.75	1	2025-08-03 20:08:11.137228	2025-08-03 20:08:11.137228	0.50	4990.37
3047	\N	57	2025-06-24	13090.00	1	2025-08-03 20:08:11.445981	2025-08-03 20:08:11.445981	0.63	8300.00
3048	\N	44	2025-06-25	3467.10	1	2025-08-03 20:08:11.681587	2025-08-03 20:08:11.681587	0.30	1040.13
3049	\N	44	2025-06-25	15742.25	1	2025-08-03 20:08:11.952665	2025-08-03 20:08:11.952665	0.39	6067.00
3050	\N	44	2025-06-25	2135.60	1	2025-08-03 20:08:12.334519	2025-08-03 20:08:12.334519	0.60	1281.36
3051	\N	45	2025-06-25	2701.74	1	2025-08-03 20:08:12.577381	2025-08-03 20:08:12.577381	0.50	1350.87
3052	\N	165	2025-06-25	8106.74	1	2025-08-03 20:08:12.786111	2025-08-03 20:08:12.786111	0.60	4863.60
3053	\N	80	2025-06-25	12674.12	1	2025-08-03 20:08:12.978676	2025-08-03 20:08:12.978676	0.40	5069.65
3054	\N	80	2025-06-25	7433.21	1	2025-08-03 20:08:13.168384	2025-08-03 20:08:13.168384	0.60	4459.93
3055	\N	89	2025-06-25	9632.99	1	2025-08-03 20:08:13.348656	2025-08-03 20:08:13.348656	0.52	5000.00
3056	\N	66	2025-06-25	18233.05	1	2025-08-03 20:08:13.582268	2025-08-03 20:08:13.582268	0.50	9116.53
3057	\N	102	2025-06-25	1195.00	1	2025-08-03 20:08:13.819755	2025-08-03 20:08:13.819755	0.50	597.50
3058	\N	57	2025-06-25	1100.00	1	2025-08-03 20:08:14.006097	2025-08-03 20:08:14.006097	0.60	660.00
3059	\N	57	2025-07-15	14144.28	1	2025-08-03 20:08:14.249676	2025-08-03 20:08:14.249676	0.45	6364.92
3060	\N	57	2025-06-25	590.25	1	2025-08-03 20:08:14.620179	2025-08-03 20:08:14.620179	0.80	472.20
3061	\N	44	2025-06-26	5087.83	1	2025-08-03 20:08:14.854147	2025-08-03 20:08:14.854147	0.30	1517.33
3062	\N	44	2025-06-26	6118.58	1	2025-08-03 20:08:15.102926	2025-08-03 20:08:15.102926	0.29	1788.67
3063	\N	44	2025-06-26	5103.67	1	2025-08-03 20:08:15.354314	2025-08-03 20:08:15.354314	0.35	1788.67
3064	\N	44	2025-06-26	1680.00	1	2025-08-03 20:08:15.689146	2025-08-03 20:08:15.689146	0.60	1008.00
3065	\N	114	2025-06-26	2608.75	1	2025-08-03 20:08:15.922959	2025-08-03 20:08:15.922959	0.58	1513.00
3066	\N	114	2025-06-26	9459.40	1	2025-08-03 20:08:16.113391	2025-08-03 20:08:16.113391	0.52	4900.00
3067	\N	114	2025-06-26	13861.35	1	2025-08-03 20:08:16.331862	2025-08-03 20:08:16.331862	0.53	7400.00
3068	\N	66	2025-06-26	11014.84	1	2025-08-03 20:08:16.503233	2025-08-03 20:08:16.503233	0.55	6057.70
3069	\N	190	2025-06-26	14995.00	1	2025-08-03 20:08:16.722646	2025-08-03 20:08:16.722646	0.15	2249.25
3070	\N	247	2025-06-26	9235.00	1	2025-08-03 20:08:17.089206	2025-08-03 20:08:17.089206	0.54	5000.00
3071	\N	248	2025-06-26	5224.30	1	2025-08-03 20:08:17.59165	2025-08-03 20:08:17.59165	0.22	1160.44
3072	\N	153	2025-06-26	4785.07	1	2025-08-03 20:08:17.898209	2025-08-03 20:08:17.898209	0.50	2392.50
3073	\N	153	2025-06-26	4194.75	1	2025-08-03 20:08:18.21327	2025-08-03 20:08:18.21327	0.50	2097.06
3074	\N	87	2025-06-26	6530.00	1	2025-08-03 20:08:18.494802	2025-08-03 20:08:18.494802	0.60	3918.00
3075	\N	116	2025-06-26	6218.50	1	2025-08-03 20:08:18.834757	2025-08-03 20:08:18.834757	0.45	2800.00
3076	\N	53	2025-06-26	9344.53	1	2025-08-03 20:08:19.127212	2025-08-03 20:08:19.127212	0.56	5200.00
3077	\N	53	2025-06-26	9344.53	1	2025-08-03 20:08:19.361106	2025-08-03 20:08:19.361106	0.56	5200.00
3078	\N	44	2025-06-27	2400.60	1	2025-08-03 20:08:19.735343	2025-08-03 20:08:19.735343	0.60	1440.36
3079	\N	44	2025-06-27	15549.93	1	2025-08-03 20:08:19.996866	2025-08-03 20:08:19.996866	0.53	8244.81
3080	\N	44	2025-06-27	23369.89	1	2025-08-03 20:08:20.196947	2025-08-03 20:08:20.196947	0.23	5350.57
3081	\N	44	2025-06-27	17272.01	1	2025-08-03 20:08:20.563255	2025-08-03 20:08:20.563255	0.48	8300.77
3082	\N	187	2025-06-27	6695.00	1	2025-08-03 20:08:20.813262	2025-08-03 20:08:20.813262	0.55	3692.42
3083	\N	52	2025-06-27	10857.35	1	2025-08-03 20:08:21.008001	2025-08-03 20:08:21.008001	0.50	5429.00
3084	\N	57	2025-06-27	14578.11	1	2025-08-03 20:08:21.251193	2025-08-03 20:08:21.251193	0.55	8017.96
3085	\N	57	2025-06-27	5294.33	1	2025-08-03 20:08:21.476803	2025-08-03 20:08:21.476803	0.60	3170.00
3086	\N	57	2025-06-27	6975.00	1	2025-08-03 20:08:21.726554	2025-08-03 20:08:21.726554	0.50	3487.50
3087	\N	57	2025-06-27	9660.30	1	2025-08-03 20:08:22.190501	2025-08-03 20:08:22.190501	0.61	5866.00
3088	\N	239	2025-06-27	18616.48	1	2025-08-03 20:08:22.429704	2025-08-03 20:08:22.429704	0.45	8377.42
3089	\N	44	2025-06-30	9882.32	1	2025-08-03 20:08:22.683004	2025-08-03 20:08:22.683004	0.36	3520.81
3090	\N	231	2025-06-30	9500.00	1	2025-08-03 20:08:22.870577	2025-08-03 20:08:22.870577	0.50	4750.00
3091	\N	77	2025-06-30	6815.00	1	2025-08-03 20:08:23.101992	2025-08-03 20:08:23.101992	0.80	5452.00
3092	\N	52	2025-06-30	3915.29	1	2025-08-03 20:08:23.348936	2025-08-03 20:08:23.348936	0.50	1959.00
3093	\N	57	2025-06-30	707.90	1	2025-08-03 20:08:23.645764	2025-08-03 20:08:23.645764	0.70	495.15
3094	\N	60	2025-06-30	7090.00	1	2025-08-03 20:08:24.168226	2025-08-03 20:08:24.168226	0.50	3545.00
3095	\N	44	2025-07-01	19322.99	1	2025-08-03 20:08:24.530363	2025-08-03 20:08:24.530363	0.40	7800.00
3096	\N	44	2025-07-01	7790.00	1	2025-08-03 20:08:24.805896	2025-08-03 20:08:24.805896	0.51	3992.66
3097	\N	44	2025-07-01	4284.50	1	2025-08-03 20:08:25.070013	2025-08-03 20:08:25.070013	0.50	2142.25
3098	\N	44	2025-07-01	19539.74	1	2025-08-03 20:08:25.271357	2025-08-03 20:08:25.271357	0.21	4104.90
3099	\N	44	2025-07-01	24026.90	1	2025-08-03 20:08:25.53223	2025-08-03 20:08:25.53223	0.21	5045.26
3100	\N	249	2025-07-01	11380.00	1	2025-08-03 20:08:26.134352	2025-08-03 20:08:26.134352	0.50	5690.00
3101	\N	249	2025-07-01	5870.00	1	2025-08-03 20:08:26.346269	2025-08-03 20:08:26.346269	0.50	2935.00
3102	\N	48	2025-07-01	6290.74	1	2025-08-03 20:08:26.590557	2025-08-03 20:08:26.590557	0.48	3000.00
3103	\N	231	2025-07-01	9960.00	1	2025-08-03 20:08:26.834222	2025-08-03 20:08:26.834222	0.60	5976.00
3104	\N	84	2025-07-01	9233.53	1	2025-08-03 20:08:27.119936	2025-08-03 20:08:27.119936	0.63	5800.00
3105	\N	153	2025-07-01	5070.47	1	2025-08-03 20:08:27.555352	2025-08-03 20:08:27.555352	0.50	2535.20
3106	\N	57	2025-07-01	4400.00	1	2025-08-03 20:08:27.898403	2025-08-03 20:08:27.898403	0.59	2600.00
3107	\N	53	2025-07-01	7972.00	1	2025-08-03 20:08:28.131529	2025-08-03 20:08:28.131529	0.69	5500.00
3108	\N	53	2025-07-01	8040.98	1	2025-08-03 20:08:28.332568	2025-08-03 20:08:28.332568	0.63	5100.00
3109	\N	239	2025-07-01	8484.16	1	2025-08-03 20:08:28.617032	2025-08-03 20:08:28.617032	0.50	4242.08
3110	\N	44	2025-07-02	3792.65	1	2025-08-03 20:08:29.015923	2025-08-03 20:08:29.015923	0.56	2122.60
3111	\N	44	2025-07-02	18582.30	1	2025-08-03 20:08:29.316182	2025-08-03 20:08:29.316182	0.40	7340.47
3112	\N	44	2025-07-02	11839.25	1	2025-08-03 20:08:29.595541	2025-08-03 20:08:29.595541	0.50	5912.47
3113	\N	44	2025-07-02	28179.49	1	2025-08-03 20:08:29.872685	2025-08-03 20:08:29.872685	0.38	10609.25
3114	\N	45	2025-07-02	8755.00	1	2025-08-03 20:08:30.147323	2025-08-03 20:08:30.147323	0.50	4377.50
3115	\N	94	2025-07-02	15188.89	1	2025-08-03 20:08:30.365069	2025-08-03 20:08:30.365069	0.60	9113.33
3116	\N	94	2025-07-02	17645.13	1	2025-08-03 20:08:30.623634	2025-08-03 20:08:30.623634	0.58	10242.08
3117	\N	116	2025-07-02	7500.05	1	2025-08-03 20:08:30.920374	2025-08-03 20:08:30.920374	0.67	5000.00
3118	\N	57	2025-07-02	3627.27	1	2025-08-03 20:08:31.281587	2025-08-03 20:08:31.281587	0.63	2300.00
3119	\N	53	2025-07-02	7245.17	1	2025-08-03 20:08:31.663918	2025-08-03 20:08:31.663918	0.79	5700.00
3120	\N	44	2025-07-03	15071.70	1	2025-08-03 20:08:31.933344	2025-08-03 20:08:31.933344	0.39	5935.66
3121	\N	44	2025-07-03	6551.33	1	2025-08-03 20:08:32.295902	2025-08-03 20:08:32.295902	0.26	1675.29
3122	\N	131	2025-07-03	2332.72	1	2025-08-03 20:08:32.67107	2025-08-03 20:08:32.67107	0.60	1399.63
3123	\N	102	2025-07-03	9220.15	1	2025-08-03 20:08:33.034332	2025-08-03 20:08:33.034332	0.50	4610.08
3124	\N	102	2025-07-03	10720.00	1	2025-08-03 20:08:33.306814	2025-08-03 20:08:33.306814	0.50	5360.00
3125	\N	52	2025-07-03	12231.12	1	2025-08-03 20:08:33.641731	2025-08-03 20:08:33.641731	0.50	6116.00
3126	\N	57	2025-07-03	8960.00	1	2025-08-03 20:08:34.132514	2025-08-03 20:08:34.132514	0.52	4626.25
3127	\N	44	2025-07-07	10157.34	1	2025-08-03 20:08:34.493872	2025-08-03 20:08:34.493872	0.60	6094.40
3128	\N	44	2025-07-07	14890.24	1	2025-08-03 20:08:34.798691	2025-08-03 20:08:34.798691	0.41	6148.43
3129	\N	44	2025-07-07	2460.45	1	2025-08-03 20:08:35.066151	2025-08-03 20:08:35.066151	0.60	1476.27
3130	\N	44	2025-07-07	2530.24	1	2025-08-03 20:08:35.333071	2025-08-03 20:08:35.333071	0.60	1518.15
3131	\N	44	2025-07-07	14568.04	1	2025-08-03 20:08:35.608016	2025-08-03 20:08:35.608016	0.57	8253.01
3132	\N	44	2025-07-07	6141.40	1	2025-08-03 20:08:35.874642	2025-08-03 20:08:35.874642	0.27	1688.34
3133	\N	160	2025-07-07	11885.00	1	2025-08-03 20:08:36.235593	2025-08-03 20:08:36.235593	0.50	5942.50
3134	\N	114	2025-07-07	6375.00	1	2025-08-03 20:08:36.533503	2025-08-03 20:08:36.533503	0.50	3187.50
3135	\N	114	2025-07-07	645.00	1	2025-08-03 20:08:36.883639	2025-08-03 20:08:36.883639	0.50	322.50
3136	\N	80	2025-07-07	8531.89	1	2025-08-03 20:08:37.191036	2025-08-03 20:08:37.191036	0.48	4100.00
3137	72	80	2025-07-07	8767.17	1	2025-08-03 20:08:37.562843	2025-08-03 20:08:37.562843	0.58	5084.96
3138	\N	250	2025-07-07	2285.00	1	2025-08-03 20:08:38.03056	2025-08-03 20:08:38.03056	0.44	1000.00
3139	\N	66	2025-07-07	4390.00	1	2025-08-03 20:08:38.352115	2025-08-03 20:08:38.352115	0.50	2195.00
3140	\N	66	2025-07-07	8715.00	1	2025-08-03 20:08:38.704488	2025-08-03 20:08:38.704488	0.50	4357.50
3141	\N	110	2025-07-07	10995.00	1	2025-08-03 20:08:39.005006	2025-08-03 20:08:39.005006	0.55	6074.25
3142	81	57	2025-07-07	15589.64	1	2025-08-03 20:08:39.275139	2025-08-03 20:08:39.275139	0.51	7969.82
3143	\N	57	2025-07-07	7615.15	1	2025-08-03 20:08:39.642855	2025-08-03 20:08:39.642855	0.44	3320.00
3144	\N	57	2025-07-07	8035.12	1	2025-08-03 20:08:40.03516	2025-08-03 20:08:40.03516	0.41	3320.00
3145	\N	57	2025-07-07	5850.00	1	2025-08-03 20:08:40.43189	2025-08-03 20:08:40.43189	0.59	3460.00
3146	\N	44	2025-07-08	7542.55	1	2025-08-03 20:08:40.807052	2025-08-03 20:08:40.807052	0.26	1968.38
3147	\N	44	2025-07-08	16992.29	1	2025-08-03 20:08:41.092608	2025-08-03 20:08:41.092608	0.48	8071.42
3148	\N	44	2025-07-08	8843.25	1	2025-08-03 20:08:41.385872	2025-08-03 20:08:41.385872	0.70	6190.27
3149	\N	44	2025-07-08	1680.00	1	2025-08-03 20:08:41.693504	2025-08-03 20:08:41.693504	0.44	742.00
3150	\N	44	2025-07-08	3099.80	1	2025-08-03 20:08:42.017833	2025-08-03 20:08:42.017833	0.70	2169.86
3151	\N	45	2025-07-08	5782.57	1	2025-08-03 20:08:42.286243	2025-08-03 20:08:42.286243	0.50	2891.28
3152	\N	45	2025-07-08	2765.54	1	2025-08-03 20:08:42.558203	2025-08-03 20:08:42.558203	0.50	1382.77
3153	\N	80	2025-07-08	3927.50	1	2025-08-03 20:08:42.854658	2025-08-03 20:08:42.854658	0.56	2184.88
3154	\N	48	2025-07-08	7549.31	1	2025-08-03 20:08:43.145444	2025-08-03 20:08:43.145444	0.58	4400.00
3155	110	48	2025-07-08	11562.16	1	2025-08-03 20:08:43.381088	2025-08-03 20:08:43.381088	0.58	6700.00
3156	\N	124	2025-07-08	4990.00	1	2025-08-03 20:08:43.671267	2025-08-03 20:08:43.671267	0.75	3742.50
3157	\N	52	2025-07-08	8290.75	1	2025-08-03 20:08:43.952637	2025-08-03 20:08:43.952637	0.50	4146.00
3158	\N	116	2025-07-08	8224.91	1	2025-08-03 20:08:44.221585	2025-08-03 20:08:44.221585	0.50	4112.46
3159	\N	57	2025-07-08	12374.57	1	2025-08-03 20:08:44.606716	2025-08-03 20:08:44.606716	0.55	6806.10
3160	\N	57	2025-07-08	13774.69	1	2025-08-03 20:08:44.880434	2025-08-03 20:08:44.880434	0.59	8170.00
3161	\N	57	2025-07-08	5395.00	1	2025-08-03 20:08:45.159962	2025-08-03 20:08:45.159962	0.65	3506.75
3162	\N	57	2025-07-08	1100.00	1	2025-08-03 20:08:45.435914	2025-08-03 20:08:45.435914	0.65	715.00
3163	\N	57	2025-07-08	1100.00	1	2025-08-03 20:08:45.711831	2025-08-03 20:08:45.711831	0.65	715.00
3164	\N	60	2025-07-08	8037.13	1	2025-08-03 20:08:45.975266	2025-08-03 20:08:45.975266	0.52	4179.31
3165	\N	44	2025-07-09	11471.05	1	2025-08-03 20:08:46.363737	2025-08-03 20:08:46.363737	0.60	6882.63
3166	\N	44	2025-07-09	615.25	1	2025-08-03 20:08:46.783343	2025-08-03 20:08:46.783343	0.60	370.77
3167	\N	44	2025-07-09	3547.64	1	2025-08-03 20:08:47.061786	2025-08-03 20:08:47.061786	0.40	1403.34
3168	\N	44	2025-07-09	16500.80	1	2025-08-03 20:08:47.33521	2025-08-03 20:08:47.33521	0.43	7073.91
3169	\N	80	2025-07-09	7714.52	1	2025-08-03 20:08:47.654346	2025-08-03 20:08:47.654346	0.50	3857.26
3170	\N	146	2025-07-09	9553.98	1	2025-08-03 20:08:47.940946	2025-08-03 20:08:47.940946	0.50	4776.99
3171	\N	89	2025-07-09	3835.00	1	2025-08-03 20:08:48.242988	2025-08-03 20:08:48.242988	0.60	2301.00
3172	\N	102	2025-07-09	4765.00	1	2025-08-03 20:08:48.630365	2025-08-03 20:08:48.630365	0.00	0.00
3173	\N	57	2025-07-09	8203.35	1	2025-08-03 20:08:48.886669	2025-08-03 20:08:48.886669	0.50	4120.00
3174	\N	57	2025-07-09	8639.92	1	2025-08-03 20:08:49.312148	2025-08-03 20:08:49.312148	0.50	4315.00
3175	188	57	2025-07-09	6513.05	1	2025-08-03 20:08:49.556389	2025-08-03 20:08:49.556389	0.58	3800.00
3176	25	239	2025-07-09	8097.37	1	2025-08-03 20:08:49.83766	2025-08-03 20:08:49.83766	0.70	5668.16
3177	\N	44	2025-07-10	12986.76	1	2025-08-03 20:08:50.10886	2025-08-03 20:08:50.10886	0.60	7792.06
3178	\N	146	2025-07-10	6271.87	1	2025-08-03 20:08:50.400535	2025-08-03 20:08:50.400535	0.60	3763.12
3179	\N	65	2025-07-10	5470.04	1	2025-08-03 20:08:50.710714	2025-08-03 20:08:50.710714	0.55	3008.52
3180	\N	49	2025-07-10	16117.14	1	2025-08-03 20:08:51.113333	2025-08-03 20:08:51.113333	0.50	8058.57
3181	71	59	2025-07-10	14769.23	1	2025-08-03 20:08:51.382085	2025-08-03 20:08:51.382085	0.60	8861.54
3182	\N	44	2025-07-11	10580.10	1	2025-08-03 20:08:51.722143	2025-08-03 20:08:51.722143	0.55	5809.89
3183	\N	44	2025-07-11	17604.65	1	2025-08-03 20:08:52.090464	2025-08-03 20:08:52.090464	0.60	10562.79
3184	\N	84	2025-07-11	3525.00	1	2025-08-03 20:08:52.424265	2025-08-03 20:08:52.424265	0.78	2750.00
3185	\N	251	2025-07-11	1173.84	1	2025-08-03 20:08:53.033751	2025-08-03 20:08:53.033751	0.30	352.15
3186	\N	87	2025-07-11	6435.00	1	2025-08-03 20:08:53.339566	2025-08-03 20:08:53.339566	0.50	3217.50
3187	\N	44	2025-07-11	16500.80	1	2025-08-03 20:08:53.639959	2025-08-03 20:08:53.639959	0.43	7073.91
3188	\N	211	2025-07-11	7214.22	1	2025-08-03 20:08:53.919462	2025-08-03 20:08:53.919462	0.65	4689.24
3189	\N	211	2025-07-11	7815.47	1	2025-08-03 20:08:54.202083	2025-08-03 20:08:54.202083	0.65	5080.06
3190	\N	252	2025-07-11	13065.61	1	2025-08-03 20:08:54.75284	2025-08-03 20:08:54.75284	0.50	6532.81
3191	\N	109	2025-07-14	11960.00	1	2025-08-03 20:08:55.24593	2025-08-03 20:08:55.24593	0.55	6578.00
3192	\N	44	2025-07-14	19538.44	1	2025-08-03 20:08:55.632547	2025-08-03 20:08:55.632547	0.22	4351.67
3193	\N	57	2025-07-14	4734.85	1	2025-08-03 20:08:55.908648	2025-08-03 20:08:55.908648	0.60	2840.00
3194	\N	44	2025-07-14	7520.00	1	2025-08-03 20:08:56.180426	2025-08-03 20:08:56.180426	0.60	4512.00
3195	\N	81	2025-07-14	1135.00	1	2025-08-03 20:08:56.526058	2025-08-03 20:08:56.526058	0.60	681.00
3196	\N	45	2025-07-14	10884.84	1	2025-08-03 20:08:56.972037	2025-08-03 20:08:56.972037	0.50	5442.42
3197	\N	44	2025-07-14	17501.65	1	2025-08-03 20:08:57.328862	2025-08-03 20:08:57.328862	0.44	7762.69
3198	\N	44	2025-07-14	13641.87	1	2025-08-03 20:08:57.72211	2025-08-03 20:08:57.72211	0.39	5275.00
3199	\N	48	2025-07-14	10143.08	1	2025-08-03 20:08:58.162319	2025-08-03 20:08:58.162319	0.59	6000.00
3200	\N	44	2025-07-14	1323.75	1	2025-08-03 20:08:58.538854	2025-08-03 20:08:58.538854	0.60	794.25
3201	\N	53	2025-07-14	6140.30	1	2025-08-03 20:08:58.777413	2025-08-03 20:08:58.777413	0.53	3250.00
3202	\N	253	2025-07-14	12493.77	1	2025-08-03 20:08:59.544782	2025-08-03 20:08:59.544782	0.60	7500.00
3203	\N	44	2025-07-14	13952.35	1	2025-08-03 20:09:00.006091	2025-08-03 20:09:00.006091	0.55	7673.80
3204	\N	184	2025-07-14	6560.00	1	2025-08-03 20:09:00.385923	2025-08-03 20:09:00.385923	0.50	3280.00
3205	\N	76	2025-07-14	6859.80	1	2025-08-03 20:09:00.680224	2025-08-03 20:09:00.680224	0.50	3430.00
3206	\N	57	2025-07-14	8437.83	1	2025-08-03 20:09:01.08075	2025-08-03 20:09:01.08075	0.59	4990.00
3207	\N	103	2025-07-14	7165.32	1	2025-08-03 20:09:01.424058	2025-08-03 20:09:01.424058	0.63	4500.00
3208	\N	53	2025-07-14	10350.00	1	2025-08-03 20:09:01.69749	2025-08-03 20:09:01.69749	0.58	6000.00
3209	\N	57	2025-07-14	11578.55	1	2025-08-03 20:09:02.063184	2025-08-03 20:09:02.063184	0.50	5789.27
3210	\N	102	2025-07-14	1955.10	1	2025-08-03 20:09:02.386824	2025-08-03 20:09:02.386824	0.77	1496.25
3211	\N	44	2025-07-15	8520.07	1	2025-08-03 20:09:02.722278	2025-08-03 20:09:02.722278	0.60	5112.04
3212	\N	71	2025-07-15	5687.64	1	2025-08-03 20:09:03.012289	2025-08-03 20:09:03.012289	0.50	2843.80
3213	\N	102	2025-07-15	47925.45	1	2025-08-03 20:09:03.280086	2025-08-03 20:09:03.280086	0.50	23962.73
3214	\N	57	2025-07-15	9437.83	1	2025-08-03 20:09:03.558404	2025-08-03 20:09:03.558404	0.59	5560.00
3215	\N	55	2025-07-15	5624.61	1	2025-08-03 20:09:03.767415	2025-08-03 20:09:03.767415	0.65	3656.00
3216	171	57	2025-07-15	21555.60	1	2025-08-03 20:09:04.077898	2025-08-03 20:09:04.077898	0.60	12840.00
3217	\N	84	2025-07-15	7210.25	1	2025-08-03 20:09:04.459938	2025-08-03 20:09:04.459938	0.63	4520.00
3218	\N	57	2025-07-15	11545.00	1	2025-08-03 20:09:04.724931	2025-08-03 20:09:04.724931	0.20	2309.00
3219	\N	44	2025-07-15	3667.16	1	2025-08-03 20:09:04.99661	2025-08-03 20:09:04.99661	0.60	2200.30
3220	17	76	2025-07-15	14036.21	1	2025-08-03 20:09:05.26578	2025-08-03 20:09:05.26578	0.50	7018.00
3221	\N	53	2025-07-15	11167.83	1	2025-08-03 20:09:05.531532	2025-08-03 20:09:05.531532	0.50	5600.00
\.


--
-- TOC entry 4950 (class 0 OID 90818)
-- Dependencies: 239
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, first_name, last_name, email, password_hash, created_at, updated_at, phone_number, status) FROM stdin;
1	huzaifa	khalil	huzaifa@gmail.com	$2b$10$lkJiPEGK6OLtj9/gdSvzoOOdmeCSU2I5MlTdla8.LUJanI3wli/7W	2025-08-04 08:01:16.103595	2025-08-04 08:01:16.103595	923330363987	1
\.


--
-- TOC entry 4968 (class 0 OID 0)
-- Dependencies: 218
-- Name: attornies_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.attornies_id_seq', 259, true);


--
-- TOC entry 4969 (class 0 OID 0)
-- Dependencies: 220
-- Name: bills_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.bills_id_seq', 376, true);


--
-- TOC entry 4970 (class 0 OID 0)
-- Dependencies: 222
-- Name: locations_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.locations_id_seq', 10, true);


--
-- TOC entry 4971 (class 0 OID 0)
-- Dependencies: 224
-- Name: patient_attorny_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.patient_attorny_log_id_seq', 131, true);


--
-- TOC entry 4972 (class 0 OID 0)
-- Dependencies: 226
-- Name: patient_location_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.patient_location_log_id_seq', 188, true);


--
-- TOC entry 4973 (class 0 OID 0)
-- Dependencies: 228
-- Name: patients_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.patients_id_seq', 250, true);


--
-- TOC entry 4974 (class 0 OID 0)
-- Dependencies: 230
-- Name: providers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.providers_id_seq', 24, true);


--
-- TOC entry 4975 (class 0 OID 0)
-- Dependencies: 232
-- Name: refresh_tokens_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.refresh_tokens_id_seq', 1, true);


--
-- TOC entry 4976 (class 0 OID 0)
-- Dependencies: 234
-- Name: rule_attorneys_mapping_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.rule_attorneys_mapping_id_seq', 4, true);


--
-- TOC entry 4977 (class 0 OID 0)
-- Dependencies: 236
-- Name: rules_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.rules_id_seq', 9, true);


--
-- TOC entry 4978 (class 0 OID 0)
-- Dependencies: 238
-- Name: selttlements_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.selttlements_id_seq', 3221, true);


--
-- TOC entry 4979 (class 0 OID 0)
-- Dependencies: 240
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 1, true);


--
-- TOC entry 4739 (class 2606 OID 90839)
-- Name: attornies attornies_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attornies
    ADD CONSTRAINT attornies_name_key UNIQUE (name);


--
-- TOC entry 4741 (class 2606 OID 90841)
-- Name: attornies attornies_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.attornies
    ADD CONSTRAINT attornies_pkey PRIMARY KEY (id);


--
-- TOC entry 4743 (class 2606 OID 90843)
-- Name: bills bills_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_pkey PRIMARY KEY (id);


--
-- TOC entry 4745 (class 2606 OID 90845)
-- Name: locations locations_name_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.locations
    ADD CONSTRAINT locations_name_key UNIQUE (name);


--
-- TOC entry 4747 (class 2606 OID 90847)
-- Name: locations locations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.locations
    ADD CONSTRAINT locations_pkey PRIMARY KEY (id);


--
-- TOC entry 4749 (class 2606 OID 90849)
-- Name: patient_attorny_log patient_attorny_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_attorny_log
    ADD CONSTRAINT patient_attorny_log_pkey PRIMARY KEY (id);


--
-- TOC entry 4751 (class 2606 OID 90851)
-- Name: patient_location_log patient_location_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_location_log
    ADD CONSTRAINT patient_location_log_pkey PRIMARY KEY (id);


--
-- TOC entry 4753 (class 2606 OID 90853)
-- Name: patients patients_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_pkey PRIMARY KEY (id);


--
-- TOC entry 4755 (class 2606 OID 90855)
-- Name: providers providers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY (id);


--
-- TOC entry 4757 (class 2606 OID 90857)
-- Name: refresh_tokens refresh_tokens_token_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT refresh_tokens_token_key UNIQUE (token);


--
-- TOC entry 4759 (class 2606 OID 90859)
-- Name: rule_attorneys_mapping rule_attorneys_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rule_attorneys_mapping
    ADD CONSTRAINT rule_attorneys_mapping_pkey PRIMARY KEY (id);


--
-- TOC entry 4761 (class 2606 OID 90861)
-- Name: rules rules_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rules
    ADD CONSTRAINT rules_pkey PRIMARY KEY (id);


--
-- TOC entry 4763 (class 2606 OID 90863)
-- Name: settlements selttlements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.settlements
    ADD CONSTRAINT selttlements_pkey PRIMARY KEY (id);


--
-- TOC entry 4765 (class 2606 OID 90865)
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- TOC entry 4767 (class 2606 OID 90867)
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- TOC entry 4768 (class 2606 OID 90868)
-- Name: bills bills_attorney_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_attorney_id_fkey FOREIGN KEY (attorney_id) REFERENCES public.attornies(id);


--
-- TOC entry 4769 (class 2606 OID 90873)
-- Name: bills bills_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id);


--
-- TOC entry 4770 (class 2606 OID 90878)
-- Name: bills bills_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id);


--
-- TOC entry 4771 (class 2606 OID 90883)
-- Name: bills bills_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bills
    ADD CONSTRAINT bills_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.providers(id) NOT VALID;


--
-- TOC entry 4772 (class 2606 OID 90888)
-- Name: patient_attorny_log patient_attorny_log_attorney_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_attorny_log
    ADD CONSTRAINT patient_attorny_log_attorney_id_fkey FOREIGN KEY (attorney_id) REFERENCES public.attornies(id);


--
-- TOC entry 4773 (class 2606 OID 90893)
-- Name: patient_attorny_log patient_attorny_log_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_attorny_log
    ADD CONSTRAINT patient_attorny_log_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id);


--
-- TOC entry 4774 (class 2606 OID 90898)
-- Name: patient_attorny_log patient_attorny_log_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_attorny_log
    ADD CONSTRAINT patient_attorny_log_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id);


--
-- TOC entry 4775 (class 2606 OID 90903)
-- Name: patient_location_log patient_location_log_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_location_log
    ADD CONSTRAINT patient_location_log_location_id_fkey FOREIGN KEY (location_id) REFERENCES public.locations(id);


--
-- TOC entry 4776 (class 2606 OID 90908)
-- Name: patient_location_log patient_location_log_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_location_log
    ADD CONSTRAINT patient_location_log_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id);


--
-- TOC entry 4777 (class 2606 OID 90913)
-- Name: refresh_tokens refresh_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.refresh_tokens
    ADD CONSTRAINT refresh_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- TOC entry 4778 (class 2606 OID 90918)
-- Name: rule_attorneys_mapping rule_attorneys_mapping_attorney_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rule_attorneys_mapping
    ADD CONSTRAINT rule_attorneys_mapping_attorney_id_fkey FOREIGN KEY (attorney_id) REFERENCES public.attornies(id);


--
-- TOC entry 4779 (class 2606 OID 90923)
-- Name: rule_attorneys_mapping rule_attorneys_mapping_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rule_attorneys_mapping
    ADD CONSTRAINT rule_attorneys_mapping_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES public.rules(id);


--
-- TOC entry 4780 (class 2606 OID 90928)
-- Name: rules rules_provider_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.rules
    ADD CONSTRAINT rules_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES public.providers(id);


--
-- TOC entry 4781 (class 2606 OID 90933)
-- Name: settlements selttlements_attorney_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.settlements
    ADD CONSTRAINT selttlements_attorney_id_fkey FOREIGN KEY (attorney_id) REFERENCES public.attornies(id);


--
-- TOC entry 4782 (class 2606 OID 90938)
-- Name: settlements selttlements_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.settlements
    ADD CONSTRAINT selttlements_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id);


-- Completed on 2025-08-04 14:36:54

--
-- PostgreSQL database dump complete
--

