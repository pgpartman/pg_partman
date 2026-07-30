CREATE FUNCTION @extschema@.check_default(
        p_exact_count boolean DEFAULT true
        , p_ignore_infinity boolean DEFAULT false)
    RETURNS SETOF @extschema@.check_default_table
    LANGUAGE plpgsql STABLE
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

v_count                         bigint = 0;
v_default_schemaname            text;
v_default_tablename             text;
v_ignore_infinity_expression    text;
v_parent_schemaname             text;
v_parent_tablename              text;
v_row                           record;
v_sql                           text;
v_trouble                       @extschema@.check_default_table%rowtype;

BEGIN
/*
 * Function to monitor for data getting inserted into default table
 */

FOR v_row IN
    SELECT parent_table, control, time_encoder, time_decoder FROM @extschema@.part_config
LOOP
    IF p_ignore_infinity THEN
        IF v_row.time_encoder IS NOT NULL OR v_row.time_decoder IS NOT NULL THEN
            RAISE EXCEPTION 'p_ignore_infinity cannot be set when using encoded time values. part_config.time_encoder has value: %', v_time_encoder;
        END IF;

        v_ignore_infinity_expression := format(' WHERE %I NOT IN (''-infinity'', ''infinity'')', v_row.control);
    ELSE
        v_ignore_infinity_expression := '';
    END IF;

    SELECT schemaname, tablename
    INTO v_parent_schemaname, v_parent_tablename
    FROM pg_catalog.pg_tables
    WHERE schemaname = split_part(v_row.parent_table, '.', 1)::name
    AND tablename = split_part(v_row.parent_table, '.', 2)::name;

    v_sql := format('SELECT n.nspname::text, c.relname::text FROM
            pg_catalog.pg_inherits h
            JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
            JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
            WHERE h.inhparent = ''%I.%I''::regclass
            AND pg_get_expr(relpartbound, c.oid) = ''DEFAULT'''
        , v_parent_schemaname
        , v_parent_tablename);

    EXECUTE v_sql INTO v_default_schemaname, v_default_tablename;

    IF v_default_schemaname IS NOT NULL AND v_default_tablename IS NOT NULL THEN

        IF p_exact_count THEN
            v_sql := format('SELECT count(1) AS n FROM ONLY %I.%I %s', v_default_schemaname, v_default_tablename, v_ignore_infinity_expression);
        ELSE
            v_sql := format('SELECT count(1) AS n FROM (SELECT 1 FROM ONLY %I.%I LIMIT 1 %s) x', v_default_schemaname, v_default_tablename, v_ignore_infinity_expression);
        END IF;

        EXECUTE v_sql INTO v_count;

        IF v_count > 0 THEN
            v_trouble.default_table := v_default_schemaname ||'.'|| v_default_tablename;
            v_trouble.count := v_count;
            RETURN NEXT v_trouble;
        END IF;

    END IF;

    v_count := 0;

END LOOP;

RETURN;

END
$$;
