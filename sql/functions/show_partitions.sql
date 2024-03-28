CREATE FUNCTION @extschema@.show_partitions (
    p_parent_table text
    , p_order text DEFAULT 'ASC'
    , p_include_default boolean DEFAULT false
)
    RETURNS TABLE (partition_schemaname text, partition_tablename text)
    LANGUAGE plpgsql STABLE
    SET search_path = @extschema@,pg_temp
    AS $$
DECLARE

v_control               text;
v_control_type          text;
v_exact_control_type    text;
v_datetime_string       text;
v_default_sql           text;
v_epoch                 text;
v_epoch_divisor         bigint;
v_parent_schema         text;
v_parent_tablename      text;
v_partition_type        text;
v_sql                   text;

BEGIN
/*
 * Function to list all child partitions in a set in logical order.
 * Default partition is not listed by default since that's the common usage internally
 * If p_include_default is set true, default is always listed first.
 */

IF upper(p_order) NOT IN ('ASC', 'DESC') THEN
    RAISE EXCEPTION 'p_order parameter must be one of the following values: ASC, DESC';
END IF;

SELECT partition_type
    , datetime_string
    , control
    , epoch
INTO v_partition_type
    , v_datetime_string
    , v_control
    , v_epoch
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;

IF v_partition_type IS NULL THEN
    RAISE EXCEPTION 'Given parent table not managed by pg_partman: %', p_parent_table;
END IF;

SELECT n.nspname, c.relname INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_parent_table, '.', 1)::name
AND c.relname = split_part(p_parent_table, '.', 2)::name;

IF v_parent_tablename IS NULL THEN
    RAISE EXCEPTION 'Given parent table not found in system catalogs: %', p_parent_table;
END IF;

SELECT general_type, exact_type INTO v_control_type, v_exact_control_type FROM @extschema@.check_control_type(v_parent_schema, v_parent_tablename, v_control);

RAISE DEBUG 'show_partitions: v_parent_schema: %, v_parent_tablename: %, v_datetime_string: %, v_control_type: %, v_exact_control_type: %'
    , v_parent_schema
    , v_parent_tablename
    , v_datetime_string
    , v_control_type
    , v_exact_control_type;

v_sql := format('SELECT n.nspname::text AS partition_schemaname
        , c.relname::text AS partition_name
        FROM pg_catalog.pg_inherits h
        JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE h.inhparent = ''%I.%I''::regclass'
    , v_parent_schema
    , v_parent_tablename);

IF p_include_default THEN
    -- Return the default partition immediately as first item in list
    v_default_sql := v_sql || format('
        AND pg_get_expr(relpartbound, c.oid) = ''DEFAULT''');
    RAISE DEBUG 'show_partitions: v_default_sql: %', v_default_sql;
    RETURN QUERY EXECUTE v_default_sql;
END IF;

v_sql := v_sql || format('
    AND pg_get_expr(relpartbound, c.oid) != ''DEFAULT'' ');


IF v_control_type = 'time' THEN

    v_sql := v_sql || format('
        ORDER BY (regexp_match(pg_get_expr(c.relpartbound, c.oid, true), $REGEX$\(([^)]+)\) TO \(([^)]+)\)$REGEX$))[1]::text::timestamptz %s '
        , p_order);

ELSIF v_control_type = 'id' AND v_epoch <> 'none' THEN

    IF v_epoch = 'seconds' THEN
        v_epoch_divisor := 1;
    ELSIF v_epoch = 'milliseconds' THEN
        v_epoch_divisor := 1000;
    ELSIF v_epoch = 'nanoseconds' THEN
        v_epoch_divisor := 1000000000;
    END IF;

    -- Have to do a trim here because of inconsistency in quoting different integer types. Ex: bigint boundary values are quoted but int values are not
    v_sql := v_sql || format('
        ORDER BY to_timestamp(trim( BOTH $QUOTE$''$QUOTE$ from (regexp_match(pg_get_expr(c.relpartbound, c.oid, true), $REGEX$\(([^)]+)\) TO \(([^)]+)\)$REGEX$))[1]::text )::bigint /%s ) %s '
        , v_epoch_divisor
        , p_order);

ELSIF v_control_type = 'id' THEN

    IF v_partition_type = 'range' THEN
        -- Have to do a trim here because of inconsistency in quoting different integer types. Ex: bigint boundary values are quoted but int values are not
        v_sql := v_sql || format('
            ORDER BY trim( BOTH $QUOTE$''$QUOTE$ from (regexp_match(pg_get_expr(c.relpartbound, c.oid, true), $REGEX$\(([^)]+)\) TO \(([^)]+)\)$REGEX$))[1]::text )::%s %s '
            , v_exact_control_type, p_order);
    ELSIF v_partition_type = 'list' THEN
        v_sql := v_sql || format('
            ORDER BY trim((regexp_match(pg_get_expr(c.relpartbound, c.oid, true), $REGEX$FOR VALUES IN \(([^)])\)$REGEX$))[1])::%s %s '
            , v_exact_control_type , p_order);
    ELSE
        RAISE EXCEPTION 'show_partitions: Unsupported partition type found: %', v_partition_type;
    END IF;

ELSE
    RAISE EXCEPTION 'show_partitions: Unexpected code path in sort order determination. Please report the steps that lead to this error to extension maintainers.';
END IF;

RAISE DEBUG 'show_partitions: v_sql: %', v_sql;

RETURN QUERY EXECUTE v_sql;

END
$$;
