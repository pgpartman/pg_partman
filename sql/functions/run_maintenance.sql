CREATE FUNCTION @extschema@.run_maintenance(
    p_parent_table text DEFAULT NULL
    -- If these defaults change reflect them in `run_maintenance_proc`!
    , p_analyze boolean DEFAULT false
    , p_jobmon boolean DEFAULT true
)
    RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE

ex_context                      text;
ex_detail                       text;
ex_hint                         text;
ex_message                      text;
v_adv_lock                      boolean;
v_analyze                       boolean := FALSE;
v_check_subpart                 int;
v_control_type                  text;
v_create_count                  int := 0;
v_current_partition_id          bigint;
v_current_partition_timestamp   timestamptz;
v_default_tablename             text;
v_drop_count                    int := 0;
v_exact_control_type            text;
v_is_default                    text;
v_job_id                        bigint;
v_jobmon_schema                 text;
v_last_partition                text;
v_last_partition_created        boolean;
v_last_partition_id             bigint;
v_last_partition_timestamp      timestamptz;
v_max_id                        bigint;
v_max_id_default                bigint;
v_max_time_default              timestamptz;
v_max_timestamp                 timestamptz;
v_new_search_path               text;
v_next_partition_id             bigint;
v_next_partition_timestamp      timestamptz;
v_old_search_path               text;
v_parent_exists                 text;
v_parent_oid                    oid;
v_parent_schema                 text;
v_parent_tablename              text;
v_partition_expression          text;
v_premade_count                 int;
v_row                           record;
v_row_max_id                    record;
v_row_max_time                  record;
v_sql                           text;
v_step_id                       bigint;
v_step_overflow_id              bigint;
v_sub_id_max                    bigint;
v_sub_id_max_suffix             bigint;
v_sub_id_min                    bigint;
v_sub_parent                    text;
v_sub_timestamp_max             timestamptz;
v_sub_timestamp_max_suffix      timestamptz;
v_sub_timestamp_min             timestamptz;
v_tables_list_sql               text;

BEGIN
/*
 * Function to manage pre-creation of the next partitions in a set.
 * Also manages dropping old partitions if the retention option is set.
 * If p_parent_table is passed, will only run run_maintenance() on that one table (no matter what the configuration table may have set for it)
 * Otherwise, will run on all tables in the config table with p_automatic_maintenance() set to true.
 * For large partition sets, running analyze can cause maintenance to take longer than expected so is not done by default. Can set p_analyze to true to force analyze. Be aware that constraint exclusion may not work properly until an analyze on the partition set is run.
 */

v_adv_lock := pg_try_advisory_xact_lock(hashtext('pg_partman run_maintenance'));
IF v_adv_lock = 'false' THEN
    RAISE NOTICE 'Partman maintenance already running.';
    RETURN;
END IF;

IF pg_is_in_recovery() THEN
    RAISE DEBUG 'pg_partmain maintenance called on replica. Doing nothing.';
    RETURN;
END IF;

SELECT current_setting('search_path') INTO v_old_search_path;
IF length(v_old_search_path) > 0 THEN
   v_new_search_path := '@extschema@,pg_temp,'||v_old_search_path;
ELSE
    v_new_search_path := '@extschema@,pg_temp';
END IF;
IF p_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        v_new_search_path := format('%s,%s',v_jobmon_schema, v_new_search_path);
    END IF;
END IF;
EXECUTE format('SELECT set_config(%L, %L, %L)', 'search_path', v_new_search_path, 'false');

IF v_jobmon_schema IS NOT NULL THEN
    v_job_id := add_job('PARTMAN RUN MAINTENANCE');
    v_step_id := add_step(v_job_id, 'Running maintenance loop');
END IF;

v_tables_list_sql := 'SELECT parent_table
                , partition_type
                , partition_interval
                , control
                , premake
                , undo_in_progress
                , sub_partition_set_full
                , epoch
                , infinite_time_partitions
                , retention
                , ignore_default_data
                , datetime_string
                , maintenance_order
            FROM @extschema@.part_config
            WHERE undo_in_progress = false';

IF p_parent_table IS NULL THEN
    v_tables_list_sql := v_tables_list_sql || format(' AND automatic_maintenance = %L ', 'on');
ELSE
    v_tables_list_sql := v_tables_list_sql || format(' AND parent_table = %L ', p_parent_table);
END IF;

v_tables_list_sql := v_tables_list_sql || format(' ORDER BY maintenance_order ASC NULLS LAST, parent_table ASC NULLS LAST ');

RAISE DEBUG 'run_maint: v_tables_list_sql: %', v_tables_list_sql;

FOR v_row IN EXECUTE v_tables_list_sql
LOOP

    CONTINUE WHEN v_row.undo_in_progress;

    -- When sub-partitioning, retention may drop tables that were already put into the query loop values.
    -- Check if they still exist in part_config before continuing
    v_parent_exists := NULL;
    SELECT parent_table INTO v_parent_exists FROM @extschema@.part_config WHERE parent_table = v_row.parent_table;
    IF v_parent_exists IS NULL THEN
        RAISE DEBUG 'run_maint: Parent table possibly removed from part_config by retenion';
    END IF;
    CONTINUE WHEN v_parent_exists IS NULL;

    -- Check for old quarterly and ISO weekly partitioning from prior to version 5.x. Error out to avoid breaking these partition sets
    -- with new datetime_string formats
    IF v_row.datetime_string IN ('YYYY"q"Q', 'IYYY"w"IW') THEN
        RAISE EXCEPTION 'Quarterly and ISO weekly partitioning is no longer supported in pg_partman 5.0.0 and greater. Please see documentation for migrating away from these partitioning patterns. Partition set: %', v_row.parent_table;
    END IF;

    -- Check for consistent data in part_config_sub table. Was unable to get this working properly as either a constraint or trigger.
    -- Would either delay raising an error until the next write (which I cannot predict) or disallow future edits to update a sub-partition set's configuration.
    -- This way at least provides a consistent way to check that I know will run. If anyone can get a working constraint/trigger, please help!
    SELECT sub_parent INTO v_sub_parent FROM @extschema@.part_config_sub WHERE sub_parent = v_row.parent_table;
    IF v_sub_parent IS NOT NULL THEN
        SELECT count(*) INTO v_check_subpart FROM @extschema@.check_subpart_sameconfig(v_row.parent_table);
        IF v_check_subpart > 1 THEN
            RAISE EXCEPTION 'Inconsistent data in part_config_sub table. Sub-partition tables that are themselves sub-partitions cannot have differing configuration values among their siblings.
            Run this query: "SELECT * FROM @extschema@.check_subpart_sameconfig(''%'');" This should only return a single row or nothing.
            If multiple rows are returned, the results are differing configurations in the part_config_sub table for children of the given parent.
            Determine the child tables of the given parent and look up their entries based on the "part_config_sub.sub_parent" column.
            Update the differing values to be consistent for your desired values.', v_row.parent_table;
        END IF;
    END IF;

    SELECT n.nspname, c.relname, c.oid
    INTO v_parent_schema, v_parent_tablename, v_parent_oid
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = split_part(v_row.parent_table, '.', 1)::name
    AND c.relname = split_part(v_row.parent_table, '.', 2)::name;

    -- Always returns the default partition first if it exists
    SELECT partition_tablename INTO v_default_tablename
    FROM @extschema@.show_partitions(v_row.parent_table, p_include_default := true) LIMIT 1;

    SELECT pg_get_expr(relpartbound, v_parent_oid) INTO v_is_default
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n on c.relnamespace = n.oid
    WHERE n.nspname = v_parent_schema
    AND c.relname = v_default_tablename;

    IF v_is_default != 'DEFAULT' THEN
        -- Parent table will never have data, but allows code below to "just work"
        v_default_tablename := v_parent_tablename;
    END IF;

    SELECT general_type, exact_type
    INTO v_control_type, v_exact_control_type
    FROM @extschema@.check_control_type(v_parent_schema, v_parent_tablename, v_row.control);

    v_partition_expression := CASE
        WHEN v_row.epoch = 'seconds' THEN format('to_timestamp(%I)', v_row.control)
        WHEN v_row.epoch = 'milliseconds' THEN format('to_timestamp((%I/1000)::float)', v_row.control)
        WHEN v_row.epoch = 'nanoseconds' THEN format('to_timestamp((%I/1000000000)::float)', v_row.control)
        ELSE format('%I', v_row.control)
    END;
    RAISE DEBUG 'run_maint: v_partition_expression: %', v_partition_expression;

    SELECT partition_tablename INTO v_last_partition FROM @extschema@.show_partitions(v_row.parent_table, 'DESC') LIMIT 1;
    RAISE DEBUG 'run_maint: parent_table: %, v_last_partition: %', v_row.parent_table, v_last_partition;

    IF v_control_type = 'time' OR (v_control_type = 'id' AND v_row.epoch <> 'none') THEN

        -- Run retention if needed
        IF v_row.retention IS NOT NULL THEN
            v_drop_count := v_drop_count + @extschema@.drop_partition_time(v_row.parent_table);
        END IF;

        IF v_row.sub_partition_set_full THEN
            UPDATE @extschema@.part_config SET maintenance_last_run = clock_timestamp() WHERE parent_table = v_row.parent_table;
            CONTINUE;
        END IF;

        SELECT child_start_time INTO v_last_partition_timestamp
            FROM @extschema@.show_partition_info(v_parent_schema||'.'||v_last_partition, v_row.partition_interval, v_row.parent_table);

        -- Must be reset to null otherwise if the next partition set in the loop is empty, the previous partition set's value could be used
        v_current_partition_timestamp := NULL;

        -- Loop through child tables starting from highest to get current max value in partition set
        -- Avoids doing a scan on entire partition set and/or getting any values accidentally in default.
        FOR v_row_max_time IN
            SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(v_row.parent_table, 'DESC', false)
        LOOP
            EXECUTE format('SELECT max(%s)::text FROM %I.%I'
                                , v_partition_expression
                                , v_row_max_time.partition_schemaname
                                , v_row_max_time.partition_tablename
                            ) INTO v_max_timestamp;

            IF v_row.infinite_time_partitions AND v_max_timestamp < CURRENT_TIMESTAMP THEN
                -- No new data has been inserted relative to "now", but keep making child tables anyway
                v_current_partition_timestamp = CURRENT_TIMESTAMP;
                -- Nothing else to do in this case so just end early
                EXIT;
            END IF;
            IF v_max_timestamp IS NOT NULL THEN
                SELECT suffix_timestamp INTO v_current_partition_timestamp FROM @extschema@.show_partition_name(v_row.parent_table, v_max_timestamp::text);
                EXIT;
            END IF;
        END LOOP;
        IF v_row.infinite_time_partitions AND v_max_timestamp IS NULL THEN
            -- If partition set is completely empty, still keep making child tables anyway
            -- Has to be separate check outside above loop since "future" tables are likely going to be empty and make max value in that loop NULL
            v_current_partition_timestamp = CURRENT_TIMESTAMP;
        END IF;


        -- If not ignoring the default table, check for max values there. If they are there and greater than all child values, use that instead
        -- Note the default is NOT to care about data in the default, so maintenance will fail if new child table boundaries overlap with
        --  data that exists in the default. This is intentional so user removes data from default to avoid larger problems.
        IF v_row.ignore_default_data THEN
            v_max_time_default := NULL;
        ELSE
            EXECUTE format('SELECT max(%s) FROM ONLY %I.%I', v_partition_expression, v_parent_schema, v_default_tablename) INTO v_max_time_default;
        END IF;
        RAISE DEBUG 'run_maint: v_current_partition_timestamp: %, v_max_time_default: %', v_current_partition_timestamp, v_max_time_default;
        IF v_current_partition_timestamp IS NULL AND v_max_time_default IS NULL THEN
            -- Partition set is completely empty and infinite time partitions not set
            -- Nothing to do
            UPDATE @extschema@.part_config SET maintenance_last_run = clock_timestamp() WHERE parent_table = v_row.parent_table;
            CONTINUE;
        END IF;
        RAISE DEBUG 'run_maint: v_max_timestamp: %, v_current_partition_timestamp: %, v_max_time_default: %', v_max_timestamp, v_current_partition_timestamp, v_max_time_default;
        IF v_current_partition_timestamp IS NULL OR (v_max_time_default > v_current_partition_timestamp) THEN
            SELECT suffix_timestamp INTO v_current_partition_timestamp FROM @extschema@.show_partition_name(v_row.parent_table, v_max_time_default::text);
        END IF;

        -- If this is a subpartition, determine if the last child table has been made. If so, mark it as full so future maintenance runs can skip it
        SELECT sub_min::timestamptz, sub_max::timestamptz INTO v_sub_timestamp_min, v_sub_timestamp_max FROM @extschema@.check_subpartition_limits(v_row.parent_table, 'time');
        IF v_sub_timestamp_max IS NOT NULL THEN
            SELECT suffix_timestamp INTO v_sub_timestamp_max_suffix FROM @extschema@.show_partition_name(v_row.parent_table, v_sub_timestamp_max::text);
            IF v_sub_timestamp_max_suffix = v_last_partition_timestamp THEN
                -- Final partition for this set is created. Set full and skip it
                UPDATE @extschema@.part_config
                SET sub_partition_set_full = true, maintenance_last_run = clock_timestamp()
                WHERE parent_table = v_row.parent_table;
                CONTINUE;
            END IF;
        END IF;

        -- Check and see how many premade partitions there are.
        v_premade_count = round(EXTRACT('epoch' FROM age(v_last_partition_timestamp, v_current_partition_timestamp)) / EXTRACT('epoch' FROM v_row.partition_interval::interval));
        v_next_partition_timestamp := v_last_partition_timestamp;
        RAISE DEBUG 'run_maint before loop: last_partition_timestamp: %, current_partition_timestamp: %, v_premade_count: %, v_sub_timestamp_min: %, v_sub_timestamp_max: %'
            , v_last_partition_timestamp
            , v_current_partition_timestamp
            , v_premade_count
            , v_sub_timestamp_min
            , v_sub_timestamp_max;
        -- Loop premaking until config setting is met. Allows it to catch up if it fell behind or if premake changed
        WHILE (v_premade_count < v_row.premake) LOOP
            RAISE DEBUG 'run_maint: parent_table: %, v_premade_count: %, v_next_partition_timestamp: %', v_row.parent_table, v_premade_count, v_next_partition_timestamp;
            IF v_next_partition_timestamp < v_sub_timestamp_min OR v_next_partition_timestamp > v_sub_timestamp_max THEN
                -- With subpartitioning, no need to run if the timestamp is not in the parent table's range
                EXIT;
            END IF;
            BEGIN
                v_next_partition_timestamp := v_next_partition_timestamp + v_row.partition_interval::interval;
            EXCEPTION WHEN datetime_field_overflow THEN
                v_premade_count := v_row.premake; -- do this so it can exit the premake check loop and continue in the outer for loop
                IF v_jobmon_schema IS NOT NULL THEN
                    v_step_overflow_id := add_step(v_job_id, 'Attempted partition time interval is outside PostgreSQL''s supported time range.');
                    PERFORM update_step(v_step_overflow_id, 'CRITICAL', format('Child partition creation skipped for parent table: %s', v_partition_time));
                END IF;
                RAISE WARNING 'Attempted partition time interval is outside PostgreSQL''s supported time range. Child partition creation skipped for parent table %', v_row.parent_table;
                CONTINUE;
            END;

            v_last_partition_created := @extschema@.create_partition_time(v_row.parent_table
                                                        , ARRAY[v_next_partition_timestamp]);
            IF v_last_partition_created THEN
                v_analyze := true;
                v_create_count := v_create_count + 1;
            END IF;

            v_premade_count = round(EXTRACT('epoch' FROM age(v_next_partition_timestamp, v_current_partition_timestamp)) / EXTRACT('epoch' FROM v_row.partition_interval::interval));
        END LOOP;

    ELSIF v_control_type = 'id' THEN

        -- Run retention if needed
        IF v_row.retention IS NOT NULL THEN
            v_drop_count := v_drop_count + @extschema@.drop_partition_id(v_row.parent_table);
        END IF;

        IF v_row.sub_partition_set_full THEN
            UPDATE @extschema@.part_config SET maintenance_last_run = clock_timestamp() WHERE parent_table = v_row.parent_table;
            CONTINUE;
        END IF;

        -- Must be reset to null otherwise if the next partition set in the loop is empty, the previous partition set's value could be used
        v_current_partition_id := NULL;

        FOR v_row_max_id IN
            SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(v_row.parent_table, 'DESC', false)
        LOOP
            -- Loop through child tables starting from highest to get current max value in partition set
            -- Avoids doing a scan on entire partition set and/or getting any values accidentally in default.
            EXECUTE format('SELECT trunc(max(%I))::bigint FROM %I.%I'
                            , v_row.control
                            , v_row_max_id.partition_schemaname
                            , v_row_max_id.partition_tablename) INTO v_max_id;
            IF v_max_id IS NOT NULL THEN
                SELECT suffix_id INTO v_current_partition_id FROM @extschema@.show_partition_name(v_row.parent_table, v_max_id::text);
                EXIT;
            END IF;
        END LOOP;
        -- If not ignoring the default table, check for max values there. If they are there and greater than all child values, use that instead
        -- Note the default is NOT to care about data in the default, so maintenance will fail if new child table boundaries overlap with
        --  data that exists in the default. This is intentional so user removes data from default to avoid larger problems.
        IF v_row.ignore_default_data THEN
            v_max_id_default := NULL;
        ELSE
            EXECUTE format('SELECT trunc(max(%I))::bigint FROM ONLY %I.%I', v_row.control, v_parent_schema, v_default_tablename) INTO v_max_id_default;
        END IF;
        RAISE DEBUG 'run_maint: v_max_id: %, v_current_partition_id: %, v_max_id_default: %', v_max_id, v_current_partition_id, v_max_id_default;
        IF v_current_partition_id IS NULL AND v_max_id_default IS NULL THEN
            -- Partition set is completely empty. Nothing to do
            UPDATE @extschema@.part_config SET maintenance_last_run = clock_timestamp() WHERE parent_table = v_row.parent_table;
            CONTINUE;
        END IF;
        IF v_current_partition_id IS NULL OR (v_max_id_default > v_current_partition_id) THEN
            SELECT suffix_id INTO v_current_partition_id FROM @extschema@.show_partition_name(v_row.parent_table, v_max_id_default::text);
        END IF;

        SELECT child_start_id INTO v_last_partition_id
            FROM @extschema@.show_partition_info(v_parent_schema||'.'||v_last_partition, v_row.partition_interval, v_row.parent_table);
        -- Determine if this table is a child of a subpartition parent. If so, get limits to see if run_maintenance even needs to run for it.
        SELECT sub_min::bigint, sub_max::bigint INTO v_sub_id_min, v_sub_id_max FROM @extschema@.check_subpartition_limits(v_row.parent_table, 'id');

        IF v_sub_id_max IS NOT NULL THEN
            SELECT suffix_id INTO v_sub_id_max_suffix FROM @extschema@.show_partition_name(v_row.parent_table, v_sub_id_max::text);
            IF v_sub_id_max_suffix = v_last_partition_id THEN
                -- Final partition for this set is created. Set full and skip it
                UPDATE @extschema@.part_config
                SET sub_partition_set_full = true, maintenance_last_run = clock_timestamp()
                WHERE parent_table = v_row.parent_table;
                CONTINUE;
            END IF;
        END IF;

        v_next_partition_id := v_last_partition_id;
        v_premade_count := ((v_last_partition_id - v_current_partition_id) / v_row.partition_interval::bigint);
        -- Loop premaking until config setting is met. Allows it to catch up if it fell behind or if premake changed.
        RAISE DEBUG 'run_maint: before child creation loop: parent_table: %, v_last_partition_id: %, v_premade_count: %, v_next_partition_id: %', v_row.parent_table, v_last_partition_id, v_premade_count, v_next_partition_id;
        WHILE (v_premade_count < v_row.premake) LOOP
            RAISE DEBUG 'run_maint: parent_table: %, v_premade_count: %, v_next_partition_id: %', v_row.parent_table, v_premade_count, v_next_partition_id;
            IF v_next_partition_id < v_sub_id_min OR v_next_partition_id > v_sub_id_max THEN
                -- With subpartitioning, no need to run if the id is not in the parent table's range
                EXIT;
            END IF;
            v_next_partition_id := v_next_partition_id + v_row.partition_interval::bigint;
            v_last_partition_created := @extschema@.create_partition_id(v_row.parent_table, ARRAY[v_next_partition_id]);
            IF v_last_partition_created THEN
                v_analyze := true;
                v_create_count := v_create_count + 1;
            END IF;
            v_premade_count := ((v_next_partition_id - v_current_partition_id) / v_row.partition_interval::bigint);
        END LOOP;

    END IF; -- end main IF check for time or id

    IF v_analyze AND p_analyze THEN
        IF v_jobmon_schema IS NOT NULL THEN
            v_step_id := add_step(v_job_id, format('Analyzing partition set: %s', v_row.parent_table));
        END IF;

        EXECUTE format('ANALYZE %I.%I',v_parent_schema, v_parent_tablename);

        IF v_jobmon_schema IS NOT NULL THEN
            PERFORM update_step(v_step_id, 'OK', 'Done');
        END IF;
    END IF;

    UPDATE @extschema@.part_config SET maintenance_last_run = clock_timestamp() WHERE parent_table = v_row.parent_table;

END LOOP; -- end of main loop through part_config

IF v_jobmon_schema IS NOT NULL THEN
    v_step_id := add_step(v_job_id, format('Finished maintenance'));
    PERFORM update_step(v_step_id, 'OK', format('Partition maintenance finished. %s partitions made. %s partitions dropped.', v_create_count, v_drop_count));
    IF v_step_overflow_id IS NOT NULL THEN
        PERFORM fail_job(v_job_id);
    ELSE
        PERFORM close_job(v_job_id);
    END IF;
END IF;

EXECUTE format('SELECT set_config(%L, %L, %L)', 'search_path', v_old_search_path, 'false');

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS ex_message = MESSAGE_TEXT,
                                ex_context = PG_EXCEPTION_CONTEXT,
                                ex_detail = PG_EXCEPTION_DETAIL,
                                ex_hint = PG_EXCEPTION_HINT;
        IF v_jobmon_schema IS NOT NULL THEN
            IF v_job_id IS NULL THEN
                EXECUTE format('SELECT %I.add_job(''PARTMAN RUN MAINTENANCE'')', v_jobmon_schema) INTO v_job_id;
                EXECUTE format('SELECT %I.add_step(%s, ''EXCEPTION before job logging started'')', v_jobmon_schema, v_job_id, p_parent_table) INTO v_step_id;
            ELSIF v_step_id IS NULL THEN
                EXECUTE format('SELECT %I.add_step(%s, ''EXCEPTION before first step logged'')', v_jobmon_schema, v_job_id) INTO v_step_id;
            END IF;
            EXECUTE format('SELECT %I.update_step(%s, ''CRITICAL'', %L)', v_jobmon_schema, v_step_id, 'ERROR: '||coalesce(SQLERRM,'unknown'));
            EXECUTE format('SELECT %I.fail_job(%s)', v_jobmon_schema, v_job_id);
        END IF;
        RAISE EXCEPTION '%
CONTEXT: %
DETAIL: %
HINT: %', ex_message, ex_context, ex_detail, ex_hint;
END
$$;
