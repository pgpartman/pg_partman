/*
 * Function to list all child partitions in a set in logical order.
 */
CREATE FUNCTION show_partitions (p_parent_table text, p_order text DEFAULT 'ASC') RETURNS TABLE (partition_schemaname text, partition_tablename text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = @extschema@, pg_temp 
    AS $$
DECLARE

v_datetime_string       text;
v_parent_schema         text;
v_parent_tablename      text;
v_partition_interval    text;
v_quarter               text;
v_type                  text;
v_year                  text;

BEGIN

IF upper(p_order) NOT IN ('ASC', 'DESC') THEN
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

SELECT schemaname, tablename INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_tables
WHERE schemaname = split_part(p_parent_table, '.', 1)::name
AND tablename = split_part(p_parent_table, '.', 2)::name;

IF v_type IN ('time', 'time-custom') THEN

    IF v_partition_interval::interval <> '3 months' OR (v_partition_interval::interval = '3 months' AND v_type = 'time-custom') THEN
        RETURN QUERY EXECUTE 
        format('SELECT n.nspname::text AS partition_schemaname, c.relname::text AS partition_name FROM
        pg_catalog.pg_inherits h
        JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE h.inhparent = ''%I.%I''::regclass
        ORDER BY to_timestamp(substring(c.relname from ((length(c.relname) - position(''p_'' in reverse(c.relname))) + 2) ), %L) %s'
            , v_parent_schema
            , v_parent_tablename
            , v_datetime_string
            , p_order);
    ELSE
        -- For quarterly, to_timestamp() doesn't recognize "Q" in datetime string. 
        -- First order by just the year, then order by the quarter number (should be last character in table name)
        RETURN QUERY EXECUTE 
        format('SELECT n.nspname::text AS partition_schemaname, c.relname::text AS partition_name FROM
        pg_catalog.pg_inherits h
        JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE h.inhparent = ''%I.%I''::regclass
        ORDER BY to_timestamp(substring(c.relname from ((length(c.relname) - position(''p_'' in reverse(c.relname))) + 2) for 4), ''YYYY'') %s
            , substring(reverse(c.relname) from 1 for 1) %s'
            , v_parent_schema
            , v_parent_tablename
            , p_order
            , p_order);
    END IF;

ELSIF v_type = 'id' THEN
    RETURN QUERY EXECUTE 
    format('SELECT n.nspname::text AS partition_schemaname, c.relname::text AS partition_name FROM
    pg_catalog.pg_inherits h
    JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE h.inhparent = ''%I.%I''::regclass
    ORDER BY substring(c.relname from ((length(c.relname) - position(''p_'' in reverse(c.relname))) + 2) )::bigint %s'
        , v_parent_schema
        , v_parent_tablename
        , p_order);

END IF;

END
$$;

