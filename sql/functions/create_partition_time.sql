CREATE FUNCTION @extschema@.create_partition_time(
    p_parent_table text
    , p_partition_times timestamptz[]
    , p_start_partition text DEFAULT NULL
)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE

ex_context                      text;
ex_detail                       text;
ex_hint                         text;
ex_message                      text;
v_control                       text;
v_control_type                  text;
v_datetime_string               text;
v_epoch                         text;
v_exists                        smallint;
v_inherit_privileges            boolean;
v_job_id                        bigint;
v_jobmon                        boolean;
v_jobmon_schema                 text;
v_new_search_path               text;
v_old_search_path               text;
v_parent_oid                    oid;
v_parent_schema                 text;
v_parent_tablename              text;
v_parent_tablespace             name;
v_partition_created             boolean := false;
v_partition_name                text;
v_partition_suffix              text;
v_partition_expression          text;
v_partition_interval            interval;
v_partition_timestamp_end       timestamptz;
v_partition_timestamp_start     timestamptz;
v_row                           record;
v_sql                           text;
v_step_id                       bigint;
v_step_overflow_id              bigint;
v_sub_control                   text;
v_sub_partition_type            text;
v_sub_timestamp_max             timestamptz;
v_sub_timestamp_min             timestamptz;
v_template_table                text;
v_time                          timestamptz;

BEGIN
/*
 * Function to create a child table in a time-based partition set
 */

SELECT control
    , partition_interval::interval -- this shared field also used in partition_id as bigint
    , epoch
    , jobmon
    , datetime_string
    , template_table
    , inherit_privileges
INTO v_control
    , v_partition_interval
    , v_epoch
    , v_jobmon
    , v_datetime_string
    , v_template_table
    , v_inherit_privileges
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;

IF NOT FOUND THEN
    RAISE EXCEPTION 'ERROR: no config found for %', p_parent_table;
END IF;

SELECT n.nspname
    , c.relname
    , c.oid
    , t.spcname
INTO v_parent_schema
    , v_parent_tablename
    , v_parent_oid
    , v_parent_tablespace
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
LEFT OUTER JOIN pg_catalog.pg_tablespace t ON c.reltablespace = t.oid
WHERE n.nspname = split_part(p_parent_table, '.', 1)::name
AND c.relname = split_part(p_parent_table, '.', 2)::name;

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_parent_schema, v_parent_tablename, v_control);
IF v_control_type <> 'time' THEN
    IF (v_control_type = 'id' AND v_epoch = 'none') OR v_control_type <> 'id' THEN
        RAISE EXCEPTION 'Cannot run on partition set without time based control column or epoch flag set with an id column. Found control: %, epoch: %', v_control_type, v_epoch;
    END IF;
END IF;

SELECT current_setting('search_path') INTO v_old_search_path;
IF length(v_old_search_path) > 0 THEN
   v_new_search_path := '@extschema@,pg_temp,'||v_old_search_path;
ELSE
    v_new_search_path := '@extschema@,pg_temp';
END IF;
IF v_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        v_new_search_path := format('%s,%s',v_jobmon_schema, v_new_search_path);
    END IF;
END IF;
EXECUTE format('SELECT set_config(%L, %L, %L)', 'search_path', v_new_search_path, 'false');

-- Determine if this table is a child of a subpartition parent. If so, get limits of what child tables can be created based on parent suffix
SELECT sub_min::timestamptz, sub_max::timestamptz INTO v_sub_timestamp_min, v_sub_timestamp_max FROM @extschema@.check_subpartition_limits(p_parent_table, 'time');

IF v_jobmon_schema IS NOT NULL THEN
    v_job_id := add_job(format('PARTMAN CREATE TABLE: %s', p_parent_table));
END IF;

v_partition_expression := CASE
    WHEN v_epoch = 'seconds' THEN format('to_timestamp(%I)', v_control)
    WHEN v_epoch = 'milliseconds' THEN format('to_timestamp((%I/1000)::float)', v_control)
    WHEN v_epoch = 'nanoseconds' THEN format('to_timestamp((%I/1000000000)::float)', v_control)
    ELSE format('%I', v_control)
END;
RAISE DEBUG 'create_partition_time: v_partition_expression: %', v_partition_expression;

FOREACH v_time IN ARRAY p_partition_times LOOP
    v_partition_timestamp_start := v_time;
    BEGIN
        v_partition_timestamp_end := v_time + v_partition_interval;
    EXCEPTION WHEN datetime_field_overflow THEN
        RAISE WARNING 'Attempted partition time interval is outside PostgreSQL''s supported time range.
            Child partition creation after time % skipped', v_time;
        v_step_overflow_id := add_step(v_job_id, 'Attempted partition time interval is outside PostgreSQL''s supported time range.');
        PERFORM update_step(v_step_overflow_id, 'CRITICAL', 'Child partition creation after time '||v_time||' skipped');

        CONTINUE;
    END;

    -- Do not create the child table if it's outside the bounds of the top parent.
    IF v_sub_timestamp_min IS NOT NULL THEN
        IF v_time < v_sub_timestamp_min OR v_time >= v_sub_timestamp_max THEN

            RAISE DEBUG 'create_partition_time: p_parent_table: %, v_time: %, v_sub_timestamp_min: %, v_sub_timestamp_max: %'
                    , p_parent_table, v_time, v_sub_timestamp_min, v_sub_timestamp_max;

            CONTINUE;
        END IF;
    END IF;

    -- This suffix generation code is in partition_data_time() as well
    v_partition_suffix := to_char(v_time, v_datetime_string);
    v_partition_name := @extschema@.check_name_length(v_parent_tablename, v_partition_suffix, TRUE);
    -- Check if child exists.
    SELECT count(*) INTO v_exists
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = v_parent_schema::name
    AND c.relname = v_partition_name::name;

    IF v_exists > 0 THEN
        CONTINUE;
    END IF;

    IF v_jobmon_schema IS NOT NULL THEN
        v_step_id := add_step(v_job_id, format('Creating new partition %s.%s with interval from %s to %s'
                                                , v_parent_schema
                                                , v_partition_name
                                                , v_partition_timestamp_start
                                                , v_partition_timestamp_end-'1sec'::interval));
    END IF;

    v_sql := 'CREATE';

    /*
    -- As of PG12, the unlogged/logged status of a parent table cannot be changed via an ALTER TABLE in order to affect its children.
    -- As of partman v4.2x, the unlogged state will be managed via the template table
    -- TODO Test UNLOGGED status in PG17 to see if this can be done without template yet. Add to create_partition_id then as well.
    SELECT relpersistence INTO v_unlogged
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relname = v_parent_tablename::name
    AND n.nspname = v_parent_schema::name;

    IF v_unlogged = 'u' THEN
        v_sql := v_sql || ' UNLOGGED';
    END IF;
    */

    -- Same INCLUDING list is used in create_parent()
    v_sql := v_sql || format(' TABLE %I.%I (LIKE %I.%I INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING STORAGE INCLUDING COMMENTS INCLUDING GENERATED) '
                                , v_parent_schema
                                , v_partition_name
                                , v_parent_schema
                                , v_parent_tablename);

    IF v_parent_tablespace IS NOT NULL THEN
        v_sql := format('%s TABLESPACE %I ', v_sql, v_parent_tablespace);
    END IF;

    SELECT sub_partition_type, sub_control INTO v_sub_partition_type, v_sub_control
    FROM @extschema@.part_config_sub
    WHERE sub_parent = p_parent_table;
    IF v_sub_partition_type = 'range' THEN
        v_sql :=  format('%s PARTITION BY RANGE (%I) ', v_sql, v_sub_control);
    END IF;

    RAISE DEBUG 'create_partition_time v_sql: %', v_sql;
    EXECUTE v_sql;

    IF v_template_table IS NOT NULL THEN
        PERFORM @extschema@.inherit_template_properties(p_parent_table, v_parent_schema, v_partition_name);
    END IF;

    IF v_epoch = 'none' THEN
        -- Attach with normal, time-based values for built-in constraint
        EXECUTE format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I FOR VALUES FROM (%L) TO (%L)'
            , v_parent_schema
            , v_parent_tablename
            , v_parent_schema
            , v_partition_name
            , v_partition_timestamp_start
            , v_partition_timestamp_end);
    ELSE
        -- Must attach with integer based values for built-in constraint and epoch
        IF v_epoch = 'seconds' THEN
            EXECUTE format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I FOR VALUES FROM (%L) TO (%L)'
                , v_parent_schema
                , v_parent_tablename
                , v_parent_schema
                , v_partition_name
                , EXTRACT('epoch' FROM v_partition_timestamp_start)::bigint
                , EXTRACT('epoch' FROM v_partition_timestamp_end)::bigint);
        ELSIF v_epoch = 'milliseconds' THEN
            EXECUTE format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I FOR VALUES FROM (%L) TO (%L)'
                , v_parent_schema
                , v_parent_tablename
                , v_parent_schema
                , v_partition_name
                , EXTRACT('epoch' FROM v_partition_timestamp_start)::bigint * 1000
                , EXTRACT('epoch' FROM v_partition_timestamp_end)::bigint * 1000);
        ELSIF v_epoch = 'nanoseconds' THEN
            EXECUTE format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I FOR VALUES FROM (%L) TO (%L)'
                , v_parent_schema
                , v_parent_tablename
                , v_parent_schema
                , v_partition_name
                , EXTRACT('epoch' FROM v_partition_timestamp_start)::bigint * 1000000000
                , EXTRACT('epoch' FROM v_partition_timestamp_end)::bigint * 1000000000);
        END IF;
        -- Create secondary, time-based constraint since built-in's constraint is already integer based
        EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I CHECK (%s >= %L AND %4$s < %6$L)'
            , v_parent_schema
            , v_partition_name
            , v_partition_name||'_partition_check'
            , v_partition_expression
            , v_partition_timestamp_start
            , v_partition_timestamp_end);
    END IF;

    -- NOTE: Privileges not automatically inherited. Only do so if config flag is set
    IF v_inherit_privileges = TRUE THEN
        PERFORM @extschema@.apply_privileges(v_parent_schema, v_parent_tablename, v_parent_schema, v_partition_name, v_job_id);
    END IF;

    IF v_jobmon_schema IS NOT NULL THEN
        PERFORM update_step(v_step_id, 'OK', 'Done');
    END IF;

    -- Will only loop once and only if sub_partitioning is actually configured
    -- This seemed easier than assigning a bunch of variables and doing an IF condition
    -- This column list must be kept consistent between:
    --   create_parent, check_subpart_sameconfig, create_partition_id, create_partition_time, dump_partitioned_table_definition, and table definition
    FOR v_row IN
        SELECT
            sub_parent
            , sub_control
            , sub_partition_interval
            , sub_partition_type
            , sub_premake
            , sub_automatic_maintenance
            , sub_template_table
            , sub_retention
            , sub_retention_schema
            , sub_retention_keep_index
            , sub_retention_keep_table
            , sub_epoch
            , sub_constraint_cols
            , sub_optimize_constraint
            , sub_infinite_time_partitions
            , sub_jobmon
            , sub_inherit_privileges
            , sub_constraint_valid
            , sub_date_trunc_interval
            , sub_ignore_default_data
            , sub_default_table
            , sub_maintenance_order
            , sub_retention_keep_publication
        FROM @extschema@.part_config_sub
        WHERE sub_parent = p_parent_table
    LOOP
        IF v_jobmon_schema IS NOT NULL THEN
            v_step_id := add_step(v_job_id, format('Subpartitioning %s.%s', v_parent_schema, v_partition_name));
        END IF;
        v_sql := format('SELECT @extschema@.create_parent(
                 p_parent_table := %L
                , p_control := %L
                , p_interval := %L
                , p_type := %L
                , p_default_table := %L
                , p_constraint_cols := %L
                , p_premake := %L
                , p_automatic_maintenance := %L
                , p_epoch := %L
                , p_template_table := %L
                , p_jobmon := %L
                , p_start_partition := %L
                , p_date_trunc_interval := %L )'
            , v_parent_schema||'.'||v_partition_name
            , v_row.sub_control
            , v_row.sub_partition_interval
            , v_row.sub_partition_type
            , v_row.sub_default_table
            , v_row.sub_constraint_cols
            , v_row.sub_premake
            , v_row.sub_automatic_maintenance
            , v_row.sub_epoch
            , v_row.sub_template_table
            , v_row.sub_jobmon
            , p_start_partition
            , v_row.sub_date_trunc_interval);

        RAISE DEBUG 'create_partition_time (create_parent loop): %', v_sql;
        EXECUTE v_sql;

        UPDATE @extschema@.part_config SET
            retention_schema = v_row.sub_retention_schema
            , retention_keep_table = v_row.sub_retention_keep_table
            , optimize_constraint = v_row.sub_optimize_constraint
            , infinite_time_partitions = v_row.sub_infinite_time_partitions
            , inherit_privileges = v_row.sub_inherit_privileges
            , constraint_valid = v_row.sub_constraint_valid
            , ignore_default_data = v_row.sub_ignore_default_data
            , maintenance_order = v_row.sub_maintenance_order
            , retention_keep_publication = v_row.sub_retention_keep_publication
        WHERE parent_table = v_parent_schema||'.'||v_partition_name;

    END LOOP; -- end sub partitioning LOOP

    -- NOTE: Replication identity not automatically inherited as of PG16 (revisit in future versions)
    PERFORM @extschema@.inherit_replica_identity(v_parent_schema, v_parent_tablename, v_partition_name);

    -- Manage additional constraints if set
    PERFORM @extschema@.apply_constraints(p_parent_table, p_job_id := v_job_id);

    v_partition_created := true;

END LOOP;

IF v_jobmon_schema IS NOT NULL THEN
    IF v_partition_created = false THEN
        v_step_id := add_step(v_job_id, format('No partitions created for partition set: %s. Attempted intervals: %s', p_parent_table, p_partition_times));
        PERFORM update_step(v_step_id, 'OK', 'Done');
    END IF;

    IF v_step_overflow_id IS NOT NULL THEN
        PERFORM fail_job(v_job_id);
    ELSE
        PERFORM close_job(v_job_id);
    END IF;
END IF;

EXECUTE format('SELECT set_config(%L, %L, %L)', 'search_path', v_old_search_path, 'false');

RETURN v_partition_created;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS ex_message = MESSAGE_TEXT,
                                ex_context = PG_EXCEPTION_CONTEXT,
                                ex_detail = PG_EXCEPTION_DETAIL,
                                ex_hint = PG_EXCEPTION_HINT;
        IF v_jobmon_schema IS NOT NULL THEN
            IF v_job_id IS NULL THEN
                EXECUTE format('SELECT %I.add_job(''PARTMAN CREATE TABLE: %s'')', v_jobmon_schema, p_parent_table) INTO v_job_id;
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
