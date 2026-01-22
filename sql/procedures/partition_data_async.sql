CREATE PROCEDURE @extschema@.partition_data_async (
    p_parent_table text
    , p_loop_count int DEFAULT NULL
    , p_interval text DEFAULT NULL
    , p_lock_wait int DEFAULT 0
    , p_lock_wait_tries int DEFAULT 10
    , p_wait int DEFAULT 1
    , p_order text DEFAULT 'ASC'
    , p_ignored_columns text[] DEFAULT NULL
    , p_quiet boolean DEFAULT false
)
    LANGUAGE plpgsql
    AS $$
DECLARE

v_adv_lock                          boolean;
v_analyze                           boolean;
v_async_partitioning_in_progress    text;
v_column_list_filtered              text;
v_control                           text;
v_control_type                      text;
v_default_batch_max_timestamp       timestamptz;
v_default_batch_min_timestamp       timestamptz;
v_default_interval                  text;
v_default_schemaname                text;
v_default_tablename                 text;
v_epoch                             text;
v_lock_iter                         int;
v_lock_obtained             boolean := FALSE;
v_loop_count        int := 0;
v_parent_schemaname                 text;
v_parent_tablename                  text;
v_partition_expression              text;
v_run_cleanup                       boolean;
v_sql                               text;
v_target_child_max_timestamp        timestamptz;
v_target_child_min_timestamp        timestamptz;
v_target_child_schemaname           text;
v_target_child_tablename            text;
v_temp_batch_min_timestamp          timestamptz;
v_temp_count                        int;
v_temp_exists                       text;
v_temp_storage_table                text;

BEGIN

v_adv_lock := pg_catalog.pg_try_advisory_xact_lock(hashtext('pg_partman partition_data_async'), hashtext(p_parent_table));
IF v_adv_lock = 'false' THEN
    RAISE NOTICE 'Partman partition_data_async already running for given parent table: %.', p_parent_table;
    RETURN;
END IF;

SELECT control, epoch, partition_interval, async_partitioning_in_progress
INTO v_control, v_epoch, v_default_interval, v_async_partitioning_in_progress
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;
IF NOT FOUND THEN
    RAISE EXCEPTION 'ERROR: No entry in part_config found for given table: %', p_parent_table;
END IF;

SELECT n.nspname, c.relname INTO v_parent_schemaname, v_parent_tablename
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = pg_catalog.split_part(p_parent_table, '.', 1)::name
AND c.relname = pg_catalog.split_part(p_parent_table, '.', 2)::name;
    IF v_parent_tablename IS NULL THEN
        RAISE EXCEPTION 'Unable to find given parent table in system catalogs. Ensure it is schema qualified: %', p_parent_table;
    END IF;

IF p_order <> 'ASC' THEN
    RAISE EXCEPTION 'Async partitioning currently only supports going in ascending order for data migration';
END IF;

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_parent_schemaname, v_parent_tablename, v_control);

IF v_control_type = 'id' AND v_epoch <> 'none' THEN
    v_control_type := 'time';
ELSIF v_control_type != 'time' THEN
    RAISE EXCEPTION 'Asyncronous partitioning currently only works with time-based partitioning. ID/Integer/UUID support is in development';
END IF;

SELECT n.nspname::text, c.relname::text
INTO v_default_schemaname, v_default_tablename
FROM pg_catalog.pg_inherits h
JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE h.inhparent = pg_catalog.format('%I.%I', v_parent_schemaname, v_parent_tablename)::regclass
AND pg_get_expr(relpartbound, c.oid) = 'DEFAULT';

IF v_default_tablename IS NULL THEN
    RAISE EXCEPTION 'Default table not found for given partition set: %', p_parent_table;
END IF;

v_temp_storage_table := pg_catalog.format('%I.%I', v_parent_schemaname, 'partman_tmp_storage_' || v_parent_tablename );

-- Generate filtered column list to use in SELECT/INSERT statements below. Allows for exclusion of GENERATED (or any other desired) columns.
-- TODO turn this into a function along with the full column list in other functions
SELECT pg_catalog.string_agg(quote_ident(attname), ',')
INTO v_column_list_filtered
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = v_default_schemaname
AND c.relname = v_default_tablename
AND a.attnum > 0
AND a.attisdropped = false
AND attname <> ALL(COALESCE(p_ignored_columns, ARRAY[]::text[]));

IF v_control_type = 'time' THEN

    IF p_interval::interval >= v_default_interval::interval THEN
        RAISE EXCEPTION 'The given interval (%) is greater than or equal to this partition set''s default interval (%). Please use a non-async partitioning function or procedure for a much simpler process to partition your data', p_interval, v_default_interval;
    END IF;

    --TODO turn this into a function
    v_partition_expression := CASE
        WHEN v_epoch = 'seconds' THEN pg_catalog.format('to_timestamp(%I)', v_control)
        WHEN v_epoch = 'milliseconds' THEN pg_catalog.format('to_timestamp((%I/1000)::float)', v_control)
        WHEN v_epoch = 'microseconds' THEN pg_catalog.format('to_timestamp((%I/1000000)::float)', v_control)
        WHEN v_epoch = 'nanoseconds' THEN pg_catalog.format('to_timestamp((%I/1000000000)::float)', v_control)
        ELSE pg_catalog.format('%I', v_control)
    END;

    EXECUTE pg_catalog.format('SELECT min(%s) FROM ONLY %I.%I', v_partition_expression, v_default_schemaname, v_default_tablename) INTO v_default_batch_min_timestamp;
    RAISE DEBUG 'partition_data_async: v_default_batch_min_timestamp: %', v_default_batch_min_timestamp;

    SELECT pg_catalog.format('%I.%I)', n.nspname, c.relname)
    INTO v_temp_exists
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = v_parent_schemaname
    AND c.relname = 'partman_tmp_storage_' || v_parent_tablename;

    IF v_default_batch_min_timestamp IS NOT NULL THEN
        -- only need to do this stuff once
        v_run_cleanup := true;

        IF v_temp_exists IS NOT NULL AND v_async_partitioning_in_progress IS NULL THEN
            RAISE EXCEPTION 'Found an already existing temporary storage table (%) for managing async partitioning for the partition set given: %. However this partition set was not marked as being in progress for an existing async partitioning operation. This is an unexpected condition and means a previous async partitioning operation may not have been completed properly. Please review the contents of the given temporary working table and make sure there is no data missing from the partition set before proceeding with further partitioning operations.', v_temp_exists, p_parent_table;
        ELSE
            v_sql := pg_catalog.format ('CREATE TABLE IF NOT EXISTS %s (LIKE %I.%I INCLUDING INDEXES)', v_temp_storage_table, v_parent_schemaname, v_parent_tablename);
            RAISE DEBUG 'partition_data_async: v_sql: %', v_sql;
            EXECUTE v_sql;
        END IF;
    ELSE
        RAISE NOTICE 'No data found in target partition set default table: %', p_parent_table;
        RETURN;
    END IF;

    <<outer_loop>>
    WHILE (v_default_batch_min_timestamp IS NOT NULL OR v_async_partitioning_in_progress IS NOT NULL)
    LOOP
        IF v_async_partitioning_in_progress IS NOT NULL THEN
            v_target_child_min_timestamp := v_async_partitioning_in_progress::timestamptz;
            v_target_child_max_timestamp := v_target_child_min_timestamp + v_default_interval::interval;
        ELSE
            v_async_partitioning_in_progress := v_target_child_min_timestamp::text;
        END IF;
        UPDATE @extschema@.part_config SET async_partitioning_in_progress = v_target_child_min_timestamp::text WHERE parent_table = p_parent_table;
        v_default_batch_max_timestamp := v_default_batch_min_timestamp + p_interval::interval;
        RAISE DEBUG 'partiton_data_async: before first condition in loop - v_target_child_min_timestamp: %,  v_target_child_max_timestamp: %, v_default_batch_max_timestamp: %, v_default_batch_min_timestamp: %', v_target_child_min_timestamp,  v_target_child_max_timestamp, v_default_batch_max_timestamp, v_default_batch_min_timestamp;

        IF v_target_child_min_timestamp IS NOT NULL AND v_target_child_max_timestamp IS NOT NULL AND v_target_child_tablename IS NOT NULL THEN
            IF v_default_batch_min_timestamp >= v_target_child_max_timestamp OR v_default_batch_min_timestamp IS NULL THEN
                /*
                   If first condition is true, there should be no data left in the default that would fit
                      in the current target child table due to actions below to reset the batch max value.
                      This should then allow the child table to be created.
                      OR if second condition is true and default_batch_min is NULL there still stuff left in the temp table to clean up
                */

                -- Get temp table minimum to start loop
                v_temp_batch_min_timestamp := NULL; -- Just to be sure
                EXECUTE pg_catalog.format('SELECT min(%s) FROM ONLY %s', v_partition_expression, v_temp_storage_table) INTO v_temp_batch_min_timestamp;
                RAISE DEBUG 'partition_data_async: before loop to move data out of temp - v_temp_batch_min_timestamp: %', v_temp_batch_min_timestamp;

                v_analyze := @extschema@.create_partition_time(p_parent_table, ARRAY[v_target_child_min_timestamp]);

                WHILE v_temp_batch_min_timestamp IS NOT NULL
                LOOP
                    -- start batch transaction to move data from temp to real child table
                        v_sql := pg_catalog.format('WITH partition_data AS (
                                DELETE FROM %1$s WHERE %2$s >= %3$L AND %2$s < %4$L RETURNING *)
                            INSERT INTO %5$I.%6$I (%7$s) SELECT %7$s FROM partition_data'
                            , v_temp_storage_table
                            , v_partition_expression
                            , v_temp_batch_min_timestamp
                            , v_temp_batch_min_timestamp + p_interval::interval
                            , v_target_child_schemaname
                            , v_target_child_tablename
                            , v_column_list_filtered);
                    RAISE DEBUG 'partition_data_async | move data from temp to real child: %', v_sql;
                    EXECUTE v_sql;
                    v_loop_count := v_loop_count + 1;
                    COMMIT; -- end batch transaction to move data from temp to real child table

                    EXECUTE pg_catalog.format('SELECT min(%s) FROM ONLY %s', v_partition_expression, v_temp_storage_table) INTO v_temp_batch_min_timestamp;

                    RAISE DEBUG 'partition_data_async: inside loop to move data out of temp - v_temp_batch_min_timestamp: %', v_temp_batch_min_timestamp;
                    EXIT WHEN p_loop_count > 0 AND v_loop_count >= p_loop_count;

                END LOOP; -- End inner loop to move data out of temp to real child table
                IF v_temp_batch_min_timestamp IS NULL THEN
                    v_target_child_max_timestamp := NULL;
                    v_target_child_min_timestamp := NULL;
                    v_target_child_schemaname := NULL;
                    v_target_child_tablename := NULL;
                    -- If all batches for a given child have been completed, ensure async mode has been disabled
                    UPDATE @extschema@.part_config SET async_partitioning_in_progress = NULL WHERE parent_table = p_parent_table;
                    v_async_partitioning_in_progress := NULL;
                END IF;
                EXIT outer_loop WHEN p_loop_count > 0 AND v_loop_count >= p_loop_count;
                CONTINUE outer_loop;

            ELSIF v_default_batch_max_timestamp >= v_target_child_max_timestamp THEN
                v_default_batch_max_timestamp := v_target_child_max_timestamp;
            END IF;

            IF p_lock_wait > 0  THEN
                v_lock_iter := 0;
                WHILE v_lock_iter <= 5 LOOP
                    v_lock_iter := v_lock_iter + 1;
                    RAISE DEBUG 'lock wait: v_lock_iter: %, v_lock_obtained: %', v_lock_iter, v_lock_obtained;
                    BEGIN
                        EXECUTE pg_catalog.format('SELECT %s FROM ONLY %I.%I WHERE %s >= %L AND %4$s < %6$L FOR UPDATE NOWAIT'
                            , v_column_list_filtered
                            , v_default_schemaname
                            , v_default_tablename
                            , v_partition_expression
                            , v_default_batch_min_timestamp
                            , v_default_batch_max_timestamp);
                        v_lock_obtained := TRUE;
                    EXCEPTION
                        WHEN lock_not_available THEN
                            PERFORM pg_catalog.pg_sleep( p_lock_wait / 5.0 );
                            CONTINUE;
                    END;
                    EXIT WHEN v_lock_obtained;
                END LOOP;
                IF NOT v_lock_obtained THEN
                    RAISE EXCEPTION 'Quitting due to inability to get lock on next batch of rows to be moved';
                END IF;
            END IF;

            -- start batch transaction to move data from default to temp
            EXECUTE pg_catalog.format('WITH partition_data AS (
                DELETE FROM %1$I.%2$I WHERE %3$s >= %4$L AND %3$s < %5$L RETURNING *)
            INSERT INTO %6$s (%7$s) SELECT %7$s FROM partition_data'
                , v_default_schemaname
                , v_default_tablename
                , v_partition_expression
                , v_default_batch_min_timestamp
                , v_default_batch_max_timestamp
                , v_temp_storage_table
                , v_column_list_filtered);
            COMMIT; -- end batch transaction to move data from default to temp

            v_loop_count := v_loop_count + 1;

        ELSE -- Only set these if target child table has yet to be determined or one was just created and these were reset

            EXECUTE pg_catalog.format('SELECT min(%s) FROM ONLY %s', v_partition_expression, v_temp_storage_table) INTO v_temp_batch_min_timestamp;
            RAISE DEBUG 'partition_data_async: v_temp_batch_min_timestamp: %, v_target_child_min_timestamp: %, v_target_child_max_timestamp: %', v_temp_batch_min_timestamp, v_target_child_min_timestamp, v_target_child_max_timestamp;

            IF v_temp_batch_min_timestamp IS NOT NULL THEN
                SELECT partition_schema, partition_table
                INTO v_target_child_schemaname, v_target_child_tablename
                FROM @extschema@.show_partition_name(p_parent_table, v_temp_batch_min_timestamp::text);
            ELSE
                SELECT partition_schema, partition_table
                INTO v_target_child_schemaname, v_target_child_tablename
                FROM @extschema@.show_partition_name(p_parent_table, v_default_batch_min_timestamp::text);
            END IF;
            RAISE DEBUG 'partition_data_async: v_target_child_schemaname: %, v_target_child_tablename: % ', v_target_child_schemaname, v_target_child_tablename;

            SELECT child_start_time, child_end_time
            INTO v_target_child_min_timestamp, v_target_child_max_timestamp
            FROM @extschema@.show_partition_info(v_target_child_tablename, p_parent_table := p_parent_table, p_table_exists := FALSE);

        END IF;

        EXECUTE pg_catalog.format('SELECT min(%s) FROM ONLY %I.%I', v_partition_expression, v_default_schemaname, v_default_tablename) INTO v_default_batch_min_timestamp;

        IF p_loop_count > 0 AND v_loop_count >= p_loop_count THEN
            EXIT;
        END IF;
    END LOOP outer_loop; -- end outer loop to move data from default to temp

ELSIF v_control_type = 'id' THEN

    -- Under development --

ELSE
    RAISE EXCEPTION 'partition_data_async: Unknown control type encountered: %. Please report this error with how you got to this code path.', v_control_type;
END IF;

IF v_run_cleanup THEN

    IF v_async_partitioning_in_progress IS NULL THEN

       v_sql := pg_catalog.format('DROP TABLE IF EXISTS %s', v_temp_storage_table);
        RAISE DEBUG 'partition_data_async: v_sql %', v_sql;
        EXECUTE v_sql;

    END IF;

END IF;

END
$$;
