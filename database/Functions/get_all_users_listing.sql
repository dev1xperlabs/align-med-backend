-- FUNCTION: public.get_all_users(integer, integer)

-- DROP FUNCTION IF EXISTS public.get_all_users(integer, integer);

CREATE OR REPLACE FUNCTION public.get_all_users(
	page_size integer,
	page_number integer)
    RETURNS jsonb
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'total_records', (SELECT COUNT(*) FROM users),
    'users', jsonb_agg(to_jsonb(row_data))
  )
  INTO result
  FROM (
    SELECT 
      u.id, u.first_name as firstName, u.last_name as lastName, u.email, u.status, 
      r.name AS role, u.created_at, u.updated_at
    FROM users u
    JOIN roles r ON u.role_id = r.id
    ORDER BY u.created_at DESC
    LIMIT page_size
    OFFSET (page_number - 1) * page_size
  ) AS row_data;

  RETURN result;
END;
$BODY$;

ALTER FUNCTION public.get_all_users(integer, integer)
    OWNER TO postgres;
