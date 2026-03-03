
-- NOTE: Including this again because version 5.4.2 did not update the control file properly.
--  If users already had 5.4.1 installed, it may not have installed this update so this ensure it's included.
CREATE OR REPLACE FUNCTION @extschema@.partition_data_time(
    p_parent_table text
    , p_batch_count int DEFAULT 1
    , p_batch_interval interval DEFAULT NULL
    , p_lock_wait numeric DEFAULT 0
    , p_order text DEFAULT 'ASC'
    , p_analyze boolean DEFAULT true
    , p_source_table text DEFAULT NULL
    , p_ignored_columns text[] DEFAULT NULL
    , p_override_system_value boolean DEFAULT false
    , p_ignore_infinity boolean DEFAULT false
)
    RETURNS bigint
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

v_analyze                   boolean := FALSE;
v_async_rowcount            int;
v_column_list_filtered      text;
v_column_list_full          text;
v_control                   text;
v_control_exact_type        text;
v_control_type              text;
v_datetime_string           text;
v_current_partition_name    text;
v_decoded_col               text;
v_default_exists            boolean;
v_default_schemaname        text;
v_default_tablename         text;
v_epoch                     text;
v_infinity_sql              text;
v_last_partition            text;
v_lock_iter                 int := 1;
v_lock_obtained             boolean := FALSE;
v_max_partition_timestamp   timestamptz;
v_min_partition_timestamp   timestamptz;
v_override_statement        text;
v_parent_schemaname         text;
v_parent_tablename          text;
v_partition_expression      text;
v_partition_interval        interval;
v_partition_suffix          text;
v_partition_timestamp       timestamptz[];
v_source_schemaname         text;
v_source_tablename          text;
v_rowcount                  bigint;
v_sql                       text;
v_start_control             timestamptz;
v_temp_storage_table        text;
v_time_encoder              text;
v_time_decoder              text;
v_total_rows                bigint := 0;

BEGIN
/*
 * Populate the child table(s) of a time-based partition set with data from the default or a source table
 */

SELECT partition_interval::interval
    , control
    , time_encoder
    , time_decoder
    , datetime_string
    , epoch
INTO v_partition_interval
    , v_control
    , v_time_encoder
    , v_time_decoder
    , v_datetime_string
    , v_epoch
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;
IF NOT FOUND THEN
    RAISE EXCEPTION 'ERROR: No entry in part_config found for given table:  %', p_parent_table;
END IF;

IF p_ignore_infinity THEN
    IF p_source_table IS NOT NULL THEN
        RAISE EXCEPTION 'The ignore infinity parameter is only for usage when moving data out of the default. Found that p_source_table was set: %', p_source_table;
    END IF;
    IF v_time_encoder IS NOT NULL OR v_time_decoder IS NOT NULL THEN
        RAISE EXCEPTION 'p_ignore_infinity cannot be set when using encoded time values. part_config.time_encoder has value: %', v_time_encoder;
    END IF;
END IF;

SELECT schemaname, tablename INTO v_parent_schemaname, v_parent_tablename
FROM pg_catalog.pg_tables
WHERE schemaname = split_part(p_parent_table, '.', 1)::name
AND tablename = split_part(p_parent_table, '.', 2)::name;

SELECT general_type, exact_type INTO v_control_type, v_control_exact_type FROM @extschema@.check_control_type(v_parent_schemaname, v_parent_tablename, v_control);
IF v_control_type <> 'time' THEN
    IF (v_control_type = 'id' AND v_epoch = 'none') OR v_control_type NOT IN ('text', 'id', 'uuid') OR (v_control_type IN ('text', 'uuid') AND v_time_encoder IS NULL) THEN
        RAISE EXCEPTION 'Cannot run on partition set without time based control column, an epoch flag set with an id column or time_encoder set with text column. Found control: %, epoch: %, time_encoder: %s', v_control_type, v_epoch, v_time_encoder;
    END IF;
END IF;

SELECT n.nspname::text, c.relname::text
INTO v_default_schemaname, v_default_tablename
FROM pg_catalog.pg_inherits h
JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE h.inhparent = format('%I.%I', v_parent_schemaname, v_parent_tablename)::regclass
AND pg_get_expr(relpartbound, c.oid) = 'DEFAULT';

IF p_source_table IS NOT NULL THEN
    -- Set source table to user given source table instead of default table
    v_source_schemaname := NULL;
    v_source_tablename := NULL;

    SELECT schemaname, tablename INTO v_source_schemaname, v_source_tablename
    FROM pg_catalog.pg_tables
    WHERE schemaname = split_part(p_source_table, '.', 1)::name
    AND tablename = split_part(p_source_table, '.', 2)::name;

    IF v_default_tablename IS NOT NULL THEN
        -- Cannot set source parameter to default. Otherwise things get put into a weird loop since data is getting put back into where it was just pulled out
        IF v_default_schemaname = v_source_schemaname AND v_default_tablename = v_source_tablename THEN
            RAISE EXCEPTION 'Cannot set p_source_table to the same value as the default table for this partition set. If you are moving data out of the default, please leave p_source_table unset and data will be moved out of the default table automatically.';
        END IF;
    END IF;

    IF v_source_tablename IS NULL THEN
        RAISE EXCEPTION 'Given source table does not exist in system catalogs: %', p_source_table;
    END IF;


ELSE

    IF p_batch_interval IS NOT NULL AND p_batch_interval != v_partition_interval THEN
        -- This is true because all data for a given child table must be moved out of the default partition before the child table can be created.
        -- So cannot create the child table when only some of the data has been moved out of the default partition.
        RAISE EXCEPTION 'If any interval smaller than the partition interval must be used for moving data out of the default, please use the partition_data_async() procedure.';
    END IF;

    -- Set source table to default table if p_source_table is not set, and it exists
    -- Otherwise just return with a NOTICE that no data source exists

    IF v_default_tablename IS NOT NULL THEN
        v_source_schemaname := v_default_schemaname;
        v_source_tablename := v_default_tablename;

        v_default_exists := true;

            v_temp_storage_table := format('%I', 'partman_temp_data_storage');
            EXECUTE format ('CREATE TEMP TABLE IF NOT EXISTS %s (LIKE %I.%I INCLUDING INDEXES) ON COMMIT DROP', v_temp_storage_table, v_source_schemaname, v_source_tablename);

    ELSE
        RAISE NOTICE 'No default table found when partition_data_time() was called';
        RETURN v_total_rows;
    END IF;
END IF;

IF p_batch_interval IS NULL OR p_batch_interval > v_partition_interval THEN
    p_batch_interval := v_partition_interval;
END IF;

SELECT partition_tablename INTO v_last_partition FROM @extschema@.show_partitions(p_parent_table, 'DESC') LIMIT 1;

v_partition_expression := CASE
    WHEN v_epoch = 'seconds' THEN format('to_timestamp(%I)', v_control)
    WHEN v_epoch = 'milliseconds' THEN format('to_timestamp((%I/1000)::float)', v_control)
    WHEN v_epoch = 'microseconds' THEN format('to_timestamp((%I/1000000)::float)', v_control)
    WHEN v_epoch = 'nanoseconds' THEN format('to_timestamp((%I/1000000000)::float)', v_control)
    ELSE format('%I', v_control)
END;

-- Generate filtered column list to use in SELECT/INSERT statements below. Allows for exclusion of GENERATED (or any other desired) columns.
SELECT string_agg(quote_ident(attname), ',')
INTO v_column_list_filtered
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = v_source_schemaname
AND c.relname = v_source_tablename
AND a.attnum > 0
AND a.attisdropped = false
AND attname <> ALL(COALESCE(p_ignored_columns, ARRAY[]::text[]));

-- Generate full column list to use in SELECT/INSERT statements below when temp table is in use
SELECT string_agg(quote_ident(attname), ',')
INTO v_column_list_full
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = v_source_schemaname
AND c.relname = v_source_tablename
AND a.attnum > 0
AND a.attisdropped = false;

IF p_ignore_infinity AND v_time_decoder IS NULL THEN
    v_infinity_sql := format(' WHERE %I NOT IN (''-infinity'', ''infinity'')', v_control);
ELSIF p_ignore_infinity AND v_time_decoder IS NOT NULL THEN
    RAISE EXCEPTION 'When using a decoder for partition values, infinity cannot be ignored and is generally not supported as a value.';
ELSE
    v_infinity_sql := '';
END IF;

FOR i IN 1..p_batch_count LOOP

    IF v_time_decoder IS NULL THEN
        IF p_order = 'ASC' THEN
            EXECUTE format('SELECT min(%s) FROM ONLY %I.%I %s', v_partition_expression, v_source_schemaname, v_source_tablename, v_infinity_sql) INTO v_start_control;
        ELSIF p_order = 'DESC' THEN
            EXECUTE format('SELECT max(%s) FROM ONLY %I.%I %s', v_partition_expression, v_source_schemaname, v_source_tablename, v_infinity_sql) INTO v_start_control;
        ELSE
            RAISE EXCEPTION 'Invalid value for p_order. Must be ASC or DESC';
        END IF;

    ELSE
	-- Currently time decoder function must take a text parameter. See if this can be more flexible in the future
    -- infinity value not supported in uuid columns, so shouldn't have to worry about it. Exception catches it above if user tries to ignore infinity.
        IF p_order = 'ASC' THEN
            EXECUTE format('SELECT min(%s(%s::text)) FROM ONLY %I.%I', v_time_decoder, v_partition_expression, v_source_schemaname, v_source_tablename) INTO v_start_control;
        ELSIF p_order = 'DESC' THEN
            EXECUTE format('SELECT max(%s(%s::text)) FROM ONLY %I.%I', v_time_decoder, v_partition_expression, v_source_schemaname, v_source_tablename) INTO v_start_control;
        ELSE
            RAISE EXCEPTION 'Invalid value for p_order. Must be ASC or DESC';
        END IF;
    END IF;

    IF v_start_control IS NULL THEN
       EXIT;
    END IF;

    SELECT child_start_time INTO v_min_partition_timestamp FROM @extschema@.show_partition_info(v_parent_schemaname||'.'||v_last_partition
        , v_partition_interval::text
        , p_parent_table);
    v_max_partition_timestamp := v_min_partition_timestamp + v_partition_interval;
    LOOP
        IF v_start_control >= v_min_partition_timestamp AND v_start_control < v_max_partition_timestamp THEN
            EXIT;
        ELSE
            BEGIN
                IF v_start_control >= v_max_partition_timestamp THEN
                    -- Keep going forward in time, checking if child partition time interval encompasses the current v_start_control value
                    v_min_partition_timestamp := v_max_partition_timestamp;
                    v_max_partition_timestamp := v_max_partition_timestamp + v_partition_interval;

                ELSE
                    -- Keep going backwards in time, checking if child partition time interval encompasses the current v_start_control value
                    v_max_partition_timestamp := v_min_partition_timestamp;
                    v_min_partition_timestamp := v_min_partition_timestamp - v_partition_interval;
                END IF;
            EXCEPTION WHEN datetime_field_overflow THEN
                RAISE EXCEPTION 'Attempted partition time interval is outside PostgreSQL''s supported time range.
                    Unable to create partition with interval before timestamp % ', v_min_partition_timestamp;
            END;
        END IF;
    END LOOP;

    v_partition_timestamp := ARRAY[v_min_partition_timestamp];
    IF p_order = 'ASC' THEN
        -- Ensure batch interval given as parameter doesn't cause maximum to overflow the current partition maximum
        IF (v_start_control + p_batch_interval) >= (v_min_partition_timestamp + v_partition_interval) THEN
            v_max_partition_timestamp := v_min_partition_timestamp + v_partition_interval;
        ELSE
            v_max_partition_timestamp := v_start_control + p_batch_interval;
        END IF;
    ELSIF p_order = 'DESC' THEN
        -- Must be greater than max value still in parent table since query below grabs < max
        v_max_partition_timestamp := v_min_partition_timestamp + v_partition_interval;
        -- Ensure batch interval given as parameter doesn't cause minimum to underflow current partition minimum
        IF (v_start_control - p_batch_interval) >= v_min_partition_timestamp THEN
            v_min_partition_timestamp := v_start_control - p_batch_interval;
        END IF;
    ELSE
        RAISE EXCEPTION 'Invalid value for p_order. Must be ASC or DESC';
    END IF;

-- do some locking with timeout, if required
    IF p_lock_wait > 0  THEN
        v_lock_iter := 0;
        WHILE v_lock_iter <= 5 LOOP
            v_lock_iter := v_lock_iter + 1;
            BEGIN
                v_sql := format('SELECT * FROM ONLY %I.%I WHERE %s >= %L AND %4$s < %6$L FOR UPDATE NOWAIT'
                    , v_source_schemaname
                    , v_source_tablename
                    , v_partition_expression
                    , v_min_partition_timestamp
                    , v_max_partition_timestamp);
                EXECUTE v_sql;
                v_lock_obtained := TRUE;
            EXCEPTION
                WHEN lock_not_available THEN
                    PERFORM pg_sleep( p_lock_wait / 5.0 );
                    CONTINUE;
            END;
            EXIT WHEN v_lock_obtained;
        END LOOP;
        IF NOT v_lock_obtained THEN
           RETURN -1;
        END IF;
    END IF;

    -- This suffix generation code is in create_partition_time() as well
    v_partition_suffix := to_char(v_min_partition_timestamp, v_datetime_string);
    v_current_partition_name := @extschema@.check_name_length(v_parent_tablename, v_partition_suffix, TRUE);

    IF p_override_system_value THEN
        v_override_statement = ' OVERRIDING SYSTEM VALUE ';
    ELSE
        v_override_statement = ' ';
    END IF;

    -- Create a variable to use in all scenarios below for handling encoded columns

    IF v_time_decoder IS NULL THEN
        IF v_control_exact_type = 'timestamp' THEN
            -- Conversion to text of timestamp without timezone cannot be directly compared to timestamptz
            -- that is returned by other functions and used below (See Github Issue #838)
            v_decoded_col := format('%s::timestamptz::text', v_partition_expression);
        ELSE
            v_decoded_col := format('%s::text', v_partition_expression);
        END IF;
    ELSE
        v_decoded_col := format('%s(%s::text)', v_time_decoder, v_partition_expression);
    END IF;

    IF v_default_exists THEN
        -- Child tables cannot be created if data that belongs to it exists in the default
        -- Have to move data out to temporary location, create child table, then move it back

        -- Temp table created above to avoid excessive temp creation in loop
        -- Must use full column list here since the temp table cannot have generated/identity values for defaults.
        --      This allows for all scenarios where some people may want newly generated values and others may not.
        --      Those that want them are handled by the filtered column list when moving to the real table

        -- Infinity only needs to be of concern when being removed from the default

            v_sql := format('DELETE FROM %1$I.%2$I WHERE %3$s >= %4$L AND %3$s < %5$L RETURNING *'
                , v_source_schemaname
                , v_source_tablename
                , v_decoded_col
                , v_min_partition_timestamp
                , v_max_partition_timestamp);
            v_sql := format('WITH partition_data AS (%s) INSERT INTO %2$s (%3$s) SELECT %3$s FROM partition_data'
                , v_sql
                , v_temp_storage_table
                , v_column_list_full);

            EXECUTE v_sql;

            -- Set analyze to true if a table is created
        v_analyze := @extschema@.create_partition_time(p_parent_table, v_partition_timestamp);

        EXECUTE format('WITH partition_data AS (
                DELETE FROM %s RETURNING *)
            INSERT INTO %I.%I (%4$s) %5$s SELECT %4$s FROM partition_data'
            , v_temp_storage_table
            , v_parent_schemaname
            , v_current_partition_name
            , v_column_list_filtered
            , v_override_statement);

    ELSE

        -- Set analyze to true if a table is created
        v_analyze := @extschema@.create_partition_time(p_parent_table, v_partition_timestamp);

            v_sql := format('WITH partition_data AS (
                                DELETE FROM ONLY %I.%I WHERE %3$s >= %L AND %3$s < %5$L RETURNING *)
                             INSERT INTO %6$I.%7$I (%8$s) %9$s SELECT %8$s FROM partition_data'
                                , v_source_schemaname
                                , v_source_tablename
                                , v_decoded_col
                                , v_min_partition_timestamp
                                , v_max_partition_timestamp
                                , v_parent_schemaname
                                , v_current_partition_name
                                , v_column_list_filtered
                                , v_override_statement);
            EXECUTE v_sql;

    END IF;

    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    v_total_rows := v_total_rows + v_rowcount;
    IF v_rowcount = 0 THEN
        EXIT;
    END IF;

END LOOP;

-- v_analyze is a local check if a new table is made.
-- p_analyze is a parameter to say whether to run the analyze at all. Used by create_partition() to avoid long exclusive lock or run_maintenence() to avoid long creation runs.
IF v_analyze AND p_analyze THEN
    RAISE DEBUG 'partiton_data_time: Begin analyze of %.%', v_parent_schemaname, v_parent_tablename;
    EXECUTE format('ANALYZE %I.%I', v_parent_schemaname, v_parent_tablename);
    RAISE DEBUG 'partiton_data_time: End analyze of %.%', v_parent_schemaname, v_parent_tablename;
END IF;

RETURN v_total_rows;

END
$$;


CREATE OR REPLACE FUNCTION @extschema@.inherit_template_properties(
    p_parent_table text
    , p_child_schema text
    , p_child_tablename text
)
    RETURNS boolean
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

v_child_relkind         char;
v_child_schema          text;
v_child_tablename       text;
v_child_unlogged        char;
v_dupe_found            boolean := false;
v_index_list            record;
v_parent_index_list     record;
v_parent_oid            oid;
v_parent_table          text;
v_relopt                record;
v_sql                   text;
v_template_oid          oid;
v_template_schemaname   text;
v_template_table        text;
v_template_tablename    name;
v_template_unlogged     char;
v_toast_table_oid       oid;

BEGIN
/*
 * Function to inherit the properties of the template table to newly created child tables.
 * For PG14+, used to inherit non-partition-key unique indexes & primary keys, unlogged status, and relation options
 */

SELECT parent_table, template_table
INTO v_parent_table, v_template_table
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;
IF v_parent_table IS NULL THEN
    RAISE EXCEPTION 'Given parent table has no configuration in pg_partman: %', p_parent_table;
ELSIF v_template_table IS NULL THEN
    RAISE EXCEPTION 'No template table set in configuration for given parent table: %', p_parent_table;
END IF;

SELECT c.oid INTO v_parent_oid
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_parent_table, '.', 1)::name
AND c.relname = split_part(p_parent_table, '.', 2)::name;
    IF v_parent_oid IS NULL THEN
        RAISE EXCEPTION 'Unable to find given parent table in system catalogs: %', p_parent_table;
    END IF;

SELECT n.nspname, c.relname, c.relkind INTO v_child_schema, v_child_tablename, v_child_relkind
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = p_child_schema::name
AND c.relname = p_child_tablename::name;
    IF v_child_tablename IS NULL THEN
        RAISE EXCEPTION 'Unable to find given child table in system catalogs: %.%', v_child_schema, v_child_tablename;
    END IF;

IF v_child_relkind = 'p' THEN
    -- Subpartitioned parent, do not apply properties
    RAISE DEBUG 'inherit_template_properties: found given child is subpartition parent, so properties not inherited';
    RETURN false;
END IF;

v_template_schemaname := split_part(v_template_table, '.', 1)::name;
v_template_tablename :=  split_part(v_template_table, '.', 2)::name;

SELECT c.oid INTO v_template_oid
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
LEFT OUTER JOIN pg_catalog.pg_tablespace ts ON c.reltablespace = ts.oid
WHERE n.nspname = v_template_schemaname
AND c.relname = v_template_tablename;
    IF v_template_oid IS NULL THEN
        RAISE EXCEPTION 'Unable to find configured template table in system catalogs: %', v_template_table;
    END IF;

-- Index creation (Only for unique, non-partition key indexes)
FOR v_index_list IN
    SELECT
    array_to_string(regexp_matches(pg_get_indexdef(indexrelid), ' USING .*'),',') AS statement
    , i.indisprimary
    , i.indisunique
    , ( SELECT array_agg( a.attname ORDER by x.r )
        FROM pg_catalog.pg_attribute a
        JOIN ( SELECT k, row_number() over () as r
                FROM unnest(i.indkey) k ) as x
        ON a.attnum = x.k AND a.attrelid = i.indrelid
    ) AS indkey_names
    , c.relname AS index_name
    , ts.spcname AS tablespace_name
    FROM pg_catalog.pg_index i
    JOIN pg_catalog.pg_class c ON i.indexrelid = c.oid
    LEFT OUTER JOIN pg_catalog.pg_tablespace ts ON c.reltablespace = ts.oid
    WHERE i.indrelid = v_template_oid
    AND i.indisvalid
    AND (i.indisprimary OR i.indisunique)
    ORDER BY 1
LOOP
    v_dupe_found := false;

    FOR v_parent_index_list IN
        SELECT
        array_to_string(regexp_matches(pg_get_indexdef(indexrelid), ' USING .*'),',') AS statement
        , i.indisprimary
        , ( SELECT array_agg( a.attname ORDER by x.r )
            FROM pg_catalog.pg_attribute a
            JOIN ( SELECT k, row_number() over () as r
                    FROM unnest(i.indkey) k ) as x
            ON a.attnum = x.k AND a.attrelid = i.indrelid
        ) AS indkey_names
        FROM pg_catalog.pg_index i
        WHERE i.indrelid = v_parent_oid
        AND i.indisvalid
        ORDER BY 1
    LOOP

        IF v_parent_index_list.indisprimary AND v_index_list.indisprimary THEN
            IF v_parent_index_list.indkey_names = v_index_list.indkey_names THEN
                RAISE DEBUG 'inherit_template_properties: Ignoring duplicate primary key on template table: % ', v_index_list.indkey_names;
                v_dupe_found := true;
                CONTINUE; -- only continue within this nested loop
            END IF;
        END IF;

        IF v_parent_index_list.statement = v_index_list.statement THEN
            RAISE DEBUG 'inherit_template_properties: Ignoring duplicate unique index on template table: %', v_index_list.statement;
            v_dupe_found := true;
            CONTINUE; -- only continue within this nested loop
        END IF;

    END LOOP; -- end parent index loop

    IF v_dupe_found = true THEN
        CONTINUE;
    END IF;

    IF v_index_list.indisprimary THEN
        v_sql := format('ALTER TABLE %I.%I ADD PRIMARY KEY (%s)'
                        , v_child_schema
                        , v_child_tablename
                        , '"' || array_to_string(v_index_list.indkey_names, '","') || '"');
        IF v_index_list.tablespace_name IS NOT NULL THEN
            v_sql := v_sql || format(' USING INDEX TABLESPACE %I', v_index_list.tablespace_name);
        END IF;
        RAISE DEBUG 'inherit_template_properties: Create pk: %', v_sql;
        EXECUTE v_sql;
    ELSIF v_index_list.indisunique THEN
        -- statement column should be just the portion of the index definition that defines what it actually is
        v_sql := format('CREATE UNIQUE INDEX ON %I.%I %s', v_child_schema, v_child_tablename, v_index_list.statement);
        IF v_index_list.tablespace_name IS NOT NULL THEN
            IF (ARRAY_length(regexp_matches(v_sql, ' WHERE ', 'i'), 1) > 0) THEN
                v_sql := regexp_replace(v_sql, ' WHERE ', format(' TABLESPACE %I WHERE ', v_index_list.tablespace_name), 'i');
            ELSE
                v_sql := v_sql || format(' TABLESPACE %I', v_index_list.tablespace_name);
            END IF;
        END IF;

        RAISE DEBUG 'inherit_template_properties: Create index: %', v_sql;
        EXECUTE v_sql;
    ELSE
        RAISE EXCEPTION 'inherit_template_properties: Unexpected code path in unique index creation. Please report the steps that lead to this error to extension maintainers.';
    END IF;

END LOOP;
-- End index creation

/*
UNLOGGED status.
    As of PG12, the unlogged/logged status of a parent table cannot be changed via an ALTER TABLE in order to affect its children.
    As of partman v4.2x, the unlogged state will be managed via the template table. See 4.2.0 release notes.
    As of PG18, the unlogged flag cannot be set on the parent table. But it can be set on the child tables. So it can continue to be supported
      in pg_partman via the template table for now.
*/

SELECT relpersistence INTO v_template_unlogged
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = v_template_schemaname
AND c.relname = v_template_tablename;

SELECT relpersistence INTO v_child_unlogged
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = v_child_schema::name
AND c.relname = v_child_tablename::name;

IF v_template_unlogged = 'u' AND v_child_unlogged = 'p'  THEN
    v_sql := format ('ALTER TABLE %I.%I SET UNLOGGED', v_child_schema, v_child_tablename);
    RAISE DEBUG 'inherit_template_properties: Alter UNLOGGED: %', v_sql;
    EXECUTE v_sql;
ELSIF v_template_unlogged = 'p' AND v_child_unlogged = 'u'  THEN
    v_sql := format ('ALTER TABLE %I.%I SET LOGGED', v_child_schema, v_child_tablename);
    RAISE DEBUG 'inherit_template_properties: Alter UNLOGGED: %', v_sql;
    EXECUTE v_sql;
END IF;

-- Relation options are not either not being inherited or not supported (autovac tuning) on <= PG15
FOR v_relopt IN
    SELECT unnest(reloptions) as value
    FROM pg_catalog.pg_class
    WHERE oid = v_template_oid
LOOP
    v_sql := format('ALTER TABLE %I.%I SET (%s)'
                    , v_child_schema
                    , v_child_tablename
                    , v_relopt.value);
    RAISE DEBUG 'inherit_template_properties: Set relopts: %', v_sql;
    EXECUTE v_sql;
END LOOP;

-- Get toast table options
SELECT reltoastrelid INTO v_toast_table_oid
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE c.oid = v_template_oid;

FOR v_relopt IN
    SELECT unnest(reloptions) as value
    FROM pg_catalog.pg_class
    WHERE oid = v_toast_table_oid
LOOP
    v_sql := format('ALTER TABLE %I.%I SET (toast.%s)'
                    , v_child_schema
                    , v_child_tablename
                    , v_relopt.value);
    RAISE DEBUG 'inherit_template_properties: Set toast relopts: %', v_sql;
    EXECUTE v_sql;
END LOOP;

RETURN true;

END
$$;
