CREATE FUNCTION @extschema@.show_partition_name(
    p_parent_table text, p_value text
    , OUT partition_schema text
    , OUT partition_table text
    , OUT suffix_timestamp timestamptz
    , OUT suffix_id bigint
    , OUT table_exists boolean
)
    RETURNS record
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE

v_child_end_time                timestamptz;
v_child_exists                  text;
v_child_larger                  boolean := false;
v_child_smaller                 boolean := false;
v_child_start_time              timestamptz;
v_control                       text;
v_time_encoder                  text;
v_control_type                  text;
v_datetime_string               text;
v_epoch                         text;
v_given_timestamp               timestamptz;
v_parent_schema                 text;
v_parent_tablename              text;
v_partition_interval            text;
v_row                           record;
v_type                          text;

BEGIN
/*
 * Given a parent table and partition value, return the name of the child partition it would go in.
 * If using epoch time partitioning, give the text representation of the timestamp NOT the epoch integer value (use to_timestamp() to convert epoch values).
 * Also returns just the suffix value and true if the child table exists or false if it does not
 */

SELECT partition_type
    , control
    , time_encoder
    , partition_interval
    , datetime_string
    , epoch
INTO v_type
    , v_control
    , v_time_encoder
    , v_partition_interval
    , v_datetime_string
    , v_epoch
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;

IF v_type IS NULL THEN
    RAISE EXCEPTION 'Parent table given is not managed by pg_partman (%)', p_parent_table;
END IF;

SELECT n.nspname, c.relname INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_parent_table, '.', 1)::name
AND c.relname = split_part(p_parent_table, '.', 2)::name;
IF v_parent_tablename IS NULL THEN
    RAISE EXCEPTION 'Parent table given does not exist (%)', p_parent_table;
END IF;

partition_schema := v_parent_schema;

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_parent_schema, v_parent_tablename, v_control);

IF ( (v_control_type = 'time') OR (v_control_type = 'id' AND v_epoch <> 'none') OR (v_control_type IN ('text', 'uuid')) ) THEN

    v_given_timestamp := p_value::timestamptz;
    FOR v_row IN
        SELECT partition_schemaname ||'.'|| partition_tablename AS child_table FROM @extschema@.show_partitions(p_parent_table, 'DESC')
    LOOP
        SELECT child_start_time INTO v_child_start_time
            FROM @extschema@.show_partition_info(v_row.child_table, v_partition_interval, p_parent_table);
        -- Don't use child_end_time from above function to avoid edge cases around user supplied timestamps
        v_child_end_time := v_child_start_time + v_partition_interval::interval;
        IF v_given_timestamp >= v_child_end_time THEN
            -- given value is higher than any existing child table. handled below.
            v_child_larger := true;
            EXIT;
        END IF;
        IF v_given_timestamp >= v_child_start_time THEN
            -- found target child table
            v_child_smaller := false;
            suffix_timestamp := v_child_start_time;
            EXIT;
        END IF;
        -- Should only get here if no matching child table was found. handled below.
        v_child_smaller := true;
    END LOOP;

    IF v_child_start_time IS NULL OR v_child_end_time IS NULL THEN
        -- This should never happen since there should never be a partition set without children.
        -- Handling just in case so issues can be reported with context
        RAISE EXCEPTION 'Unexpected code path encountered in show_partition_name(). Please report this issue to author with relevant partition config info.';
    END IF;

    IF v_child_larger THEN
        LOOP
            -- keep adding interval until found
            v_child_start_time := v_child_start_time + v_partition_interval::interval;
            v_child_end_time := v_child_end_time + v_partition_interval::interval;
            IF v_given_timestamp >= v_child_start_time AND v_given_timestamp < v_child_end_time THEN
                suffix_timestamp := v_child_start_time;
                EXIT;
            END IF;
        END LOOP;
    ELSIF v_child_smaller THEN
        LOOP
            -- keep subtracting interval until found
            v_child_start_time := v_child_start_time - v_partition_interval::interval;
            v_child_end_time := v_child_end_time - v_partition_interval::interval;
            IF v_given_timestamp >= v_child_start_time AND v_given_timestamp < v_child_end_time THEN
                suffix_timestamp := v_child_start_time;
                EXIT;
            END IF;
        END LOOP;
    END IF;

    partition_table := @extschema@.check_name_length(v_parent_tablename, to_char(suffix_timestamp, v_datetime_string), TRUE);

ELSIF v_control_type = 'id' THEN
    suffix_id := (p_value::bigint - (p_value::bigint % v_partition_interval::bigint));
    partition_table := @extschema@.check_name_length(v_parent_tablename, suffix_id::text, TRUE);

ELSE
    RAISE EXCEPTION 'Unexpected code path encountered in show_partition_name(). No valid control type found. Please report this issue to author with relevant partition config info.';
END IF;

SELECT tablename INTO v_child_exists
FROM pg_catalog.pg_tables
WHERE schemaname = partition_schema::name
AND tablename = partition_table::name;

IF v_child_exists IS NOT NULL THEN
    table_exists := true;
ELSE
    table_exists := false;
END IF;

RETURN;

END
$$;
