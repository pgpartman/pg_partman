/*
 * Function to list all child partitions in a set.
 */
CREATE FUNCTION show_partitions (p_parent_table text, p_order text DEFAULT 'ASC') RETURNS SETOF text
    LANGUAGE plpgsql STABLE SECURITY DEFINER 
    AS $$
DECLARE

v_datetime_string       text;
v_partition_interval    text;
v_type                  text;

BEGIN

IF p_order NOT IN ('ASC', 'DESC') THEN
    RAISE EXCEPTION 'p_order paramter must be one of the following values: ASC, DESC';
END IF;

SELECT partition_type
    , partition_interval
    , datetime_string
INTO v_type
    , v_partition_interval
    , v_datetime_string
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;

IF v_type IN ('time', 'time-custom') THEN

    RETURN QUERY EXECUTE '
    SELECT n.nspname::text ||''.''|| c.relname::text AS partition_name FROM
    pg_catalog.pg_inherits h
    JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE h.inhparent = '||quote_literal(p_parent_table)||'::regclass
      AND c.relname ~ (h.inhparent::regclass || ''_p''|| replace(regexp_replace(regexp_replace(regexp_replace('''||v_datetime_string||''',''YYYY|IYYY'',''\d{4}'',''g''),''(MI|IW|MM|DD|HH24|SS)'',''\d{2}'',''g''),''Q'',''\d{1}''),''"'','''') || ''$'')
    ORDER BY to_timestamp(substring(c.relname from ((length(c.relname) - position(''p_'' in reverse(c.relname))) + 2) ), '||quote_literal(v_datetime_string)||') ' || p_order;

ELSIF v_type = 'id' THEN

    RETURN QUERY EXECUTE '
    SELECT n.nspname::text ||''.''|| c.relname::text AS partition_name FROM
    pg_catalog.pg_inherits h
    JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE h.inhparent = '||quote_literal(p_parent_table)||'::regclass
    ORDER BY substring(c.relname from ((length(c.relname) - position(''p_'' in reverse(c.relname))) + 2) )::bigint ' || p_order;

END IF;

END
$$;


