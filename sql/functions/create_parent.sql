CREATE FUNCTION @extschema@.create_parent(
    p_parent_table text
    , p_control text
    , p_interval text
    , p_type text DEFAULT 'range'
    , p_epoch text DEFAULT 'none'
    , p_premake int DEFAULT 4
    , p_start_partition text DEFAULT NULL
    , p_default_table boolean DEFAULT true
    , p_automatic_maintenance text DEFAULT 'on'
    , p_constraint_cols text[] DEFAULT NULL
    , p_template_table text DEFAULT NULL
    , p_jobmon boolean DEFAULT true
    , p_date_trunc_interval text DEFAULT NULL
)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE

ex_context                      text;
ex_detail                       text;
ex_hint                         text;
ex_message                      text;
v_partattrs                     smallint[];
v_base_timestamp                timestamptz;
v_count                         int := 1;
v_control_type                  text;
v_control_exact_type            text;
v_datetime_string               text;
v_default_partition             text;
v_higher_control_type           text;
v_higher_parent_control         text;
v_higher_parent_epoch           text;
v_higher_parent_schema          text := split_part(p_parent_table, '.', 1);
v_higher_parent_table           text := split_part(p_parent_table, '.', 2);
v_id_interval                   bigint;
v_inherit_privileges            boolean := false; -- This is false by default so initial partition set creation doesn't require superuser.
v_job_id                        bigint;
v_jobmon_schema                 text;
v_last_partition_created        boolean;
v_max                           bigint;
v_notnull                       boolean;
v_new_search_path               text;
v_old_search_path               text;
v_parent_owner                  text;
v_parent_partition_id           bigint;
v_parent_partition_timestamp    timestamptz;
v_parent_schema                 text;
v_parent_tablename              text;
v_part_col                      text;
v_part_type                     text;
v_partition_time                timestamptz;
v_partition_time_array          timestamptz[];
v_partition_id_array            bigint[];
v_partstrat                     char;
v_row                           record;
v_sql                           text;
v_start_time                    timestamptz;
v_starting_partition_id         bigint;
v_step_id                       bigint;
v_step_overflow_id              bigint;
v_success                       boolean := false;
v_template_schema               text;
v_template_tablename            text;
v_time_interval                 interval;
v_top_parent_schema             text := split_part(p_parent_table, '.', 1);
v_top_parent_table              text := split_part(p_parent_table, '.', 2);
v_unlogged                      char;

BEGIN
/*
 * Function to turn a table into the parent of a partition set
 */

IF array_length(string_to_array(p_parent_table, '.'), 1) < 2 THEN
    RAISE EXCEPTION 'Parent table must be schema qualified';
ELSIF array_length(string_to_array(p_parent_table, '.'), 1) > 2 THEN
    RAISE EXCEPTION 'pg_partman does not support objects with periods in their names';
END IF;

IF p_interval = 'yearly'
    OR p_interval = 'quarterly'
    OR p_interval = 'monthly'
    OR p_interval  = 'weekly'
    OR p_interval = 'daily'
    OR p_interval = 'hourly'
    OR p_interval = 'half-hour'
    OR p_interval = 'quarter-hour'
THEN
    RAISE EXCEPTION 'Special partition interval values from old pg_partman versions (%) are no longer supported. Please use a supported interval time value from core PostgreSQL (https://www.postgresql.org/docs/current/datatype-datetime.html#DATATYPE-INTERVAL-INPUT)', p_interval;
END IF;

SELECT n.nspname, c.relname, c.relpersistence
INTO v_parent_schema, v_parent_tablename, v_unlogged
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_parent_table, '.', 1)::name
AND c.relname = split_part(p_parent_table, '.', 2)::name;
    IF v_parent_tablename IS NULL THEN
        RAISE EXCEPTION 'Unable to find given parent table in system catalogs. Please create parent table first: %', p_parent_table;
    END IF;

SELECT attnotnull INTO v_notnull
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE c.relname = v_parent_tablename::name
AND n.nspname = v_parent_schema::name
AND a.attname = p_control::name;
    IF (v_notnull = false OR v_notnull IS NULL) THEN
        RAISE EXCEPTION 'Control column given (%) for parent table (%) does not exist or must be set to NOT NULL', p_control, p_parent_table;
    END IF;

SELECT general_type, exact_type INTO v_control_type, v_control_exact_type
FROM @extschema@.check_control_type(v_parent_schema, v_parent_tablename, p_control);

IF v_control_type IS NULL THEN
    RAISE EXCEPTION 'pg_partman only supports partitioning of data types that are integer or date/timestamp. Supplied column is of type %', v_control_exact_type;
END IF;

IF (p_epoch <> 'none' AND v_control_type <> 'id') THEN
    RAISE EXCEPTION 'p_epoch can only be used with an integer based control column';
END IF;


IF NOT @extschema@.check_partition_type(p_type) THEN
    RAISE EXCEPTION '% is not a valid partitioning type for pg_partman', p_type;
END IF;

IF current_setting('server_version_num')::int < 140000 THEN
    RAISE EXCEPTION 'pg_partman requires PostgreSQL 14 or greater';
END IF;
-- Check if given parent table has been already set up as a partitioned table and is ranged
SELECT p.partstrat, partattrs INTO v_partstrat, v_partattrs
FROM pg_catalog.pg_partitioned_table p
JOIN pg_catalog.pg_class c ON p.partrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = v_parent_schema::name
AND c.relname = v_parent_tablename::name;

IF v_partstrat <> 'r' OR v_partstrat IS NULL THEN
    RAISE EXCEPTION 'You must have created the given parent table as ranged (not list) partitioned already. Ex: CREATE TABLE ... PARTITION BY RANGE ...)';
END IF;

IF array_length(v_partattrs, 1) > 1 THEN
    RAISE NOTICE 'pg_partman only supports single column partitioning at this time. Found % columns in given parent definition.', array_length(v_partattrs, 1);
END IF;

SELECT a.attname, t.typname
INTO v_part_col, v_part_type
FROM pg_attribute a
JOIN pg_class c ON a.attrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
JOIN pg_type t ON a.atttypid = t.oid
WHERE n.nspname = v_parent_schema::name
AND c.relname = v_parent_tablename::name
AND attnum IN (SELECT unnest(partattrs) FROM pg_partitioned_table p WHERE a.attrelid = p.partrelid);

IF p_control <> v_part_col OR v_control_exact_type <> v_part_type THEN
    RAISE EXCEPTION 'Control column and type given in arguments (%, %) does not match the control column and type of the given partition set (%, %)', p_control, v_control_exact_type, v_part_col, v_part_type;
END IF;

-- Check that control column is a usable type for pg_partman.
IF v_control_type NOT IN ('time', 'id') THEN
    RAISE EXCEPTION 'Only date/time or integer types are allowed for the control column.';
END IF;

-- Table to handle properties not managed by core PostgreSQL yet
IF p_template_table IS NULL THEN
    v_template_schema := '@extschema@';
    v_template_tablename := @extschema@.check_name_length('template_'||v_parent_schema||'_'||v_parent_tablename);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.%I (LIKE %I.%I)', v_template_schema, v_template_tablename, v_parent_schema, v_parent_tablename);

    SELECT pg_get_userbyid(c.relowner) INTO v_parent_owner
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = v_parent_schema::name
    AND c.relname = v_parent_tablename::name;

    EXECUTE format('ALTER TABLE %s.%I OWNER TO %I'
            , '@extschema@'
            , v_template_tablename
            , v_parent_owner);
ELSIF lower(p_template_table) IN ('false', 'f') THEN
    v_template_schema := NULL;
    v_template_tablename := NULL;
    RAISE DEBUG 'create_parent(): parent_table: %, skipped template table creation', p_parent_table;
ELSE
    SELECT n.nspname, c.relname INTO v_template_schema, v_template_tablename
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = split_part(p_template_table, '.', 1)::name
    AND c.relname = split_part(p_template_table, '.', 2)::name;
        IF v_template_tablename IS NULL THEN
            RAISE EXCEPTION 'Unable to find given template table in system catalogs (%). Please create template table first or leave parameter NULL to have a default one created for you.', p_parent_table;
        END IF;
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

EXECUTE format('LOCK TABLE %I.%I IN ACCESS EXCLUSIVE MODE', v_parent_schema, v_parent_tablename);

IF v_jobmon_schema IS NOT NULL THEN
    v_job_id := add_job(format('PARTMAN SETUP PARENT: %s', p_parent_table));
    v_step_id := add_step(v_job_id, format('Creating initial partitions on new parent table: %s', p_parent_table));
END IF;

-- If this parent table has siblings that are also partitioned (subpartitions), ensure this parent gets added to part_config_sub table so future maintenance will subpartition it
-- Just doing in a loop to avoid having to assign a bunch of variables (should only run once, if at all; constraint should enforce only one value.)
FOR v_row IN
    WITH parent_table AS (
        SELECT h.inhparent AS parent_oid
        FROM pg_catalog.pg_inherits h
        JOIN pg_catalog.pg_class c ON h.inhrelid = c.oid
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relname = v_parent_tablename::name
        AND n.nspname = v_parent_schema::name
    ), sibling_children AS (
        SELECT i.inhrelid::regclass::text AS tablename
        FROM pg_inherits i
        JOIN parent_table p ON i.inhparent = p.parent_oid
    )
    -- This column list must be kept consistent between:
    --   create_parent, check_subpart_sameconfig, create_partition_id, create_partition_time, dump_partitioned_table_definition and table definition
    SELECT DISTINCT
        a.sub_control
        , a.sub_partition_interval
        , a.sub_partition_type
        , a.sub_premake
        , a.sub_automatic_maintenance
        , a.sub_template_table
        , a.sub_retention
        , a.sub_retention_schema
        , a.sub_retention_keep_index
        , a.sub_retention_keep_table
        , a.sub_epoch
        , a.sub_constraint_cols
        , a.sub_optimize_constraint
        , a.sub_infinite_time_partitions
        , a.sub_jobmon
        , a.sub_inherit_privileges
        , a.sub_constraint_valid
        , a.sub_date_trunc_interval
        , a.sub_ignore_default_data
        , a.sub_default_table
    FROM @extschema@.part_config_sub a
    JOIN sibling_children b on a.sub_parent = b.tablename LIMIT 1
LOOP
    INSERT INTO @extschema@.part_config_sub (
        sub_parent
        , sub_partition_type
        , sub_control
        , sub_partition_interval
        , sub_constraint_cols
        , sub_premake
        , sub_retention
        , sub_retention_schema
        , sub_retention_keep_table
        , sub_retention_keep_index
        , sub_automatic_maintenance
        , sub_epoch
        , sub_optimize_constraint
        , sub_infinite_time_partitions
        , sub_jobmon
        , sub_template_table
        , sub_inherit_privileges
        , sub_constraint_valid
        , sub_date_trunc_interval
        , sub_ignore_default_data)
    VALUES (
        p_parent_table
        , v_row.sub_partition_type
        , v_row.sub_control
        , v_row.sub_partition_interval
        , v_row.sub_constraint_cols
        , v_row.sub_premake
        , v_row.sub_retention
        , v_row.sub_retention_schema
        , v_row.sub_retention_keep_index
        , v_row.sub_retention_keep_table
        , v_row.sub_automatic_maintenance
        , v_row.sub_epoch
        , v_row.sub_optimize_constraint
        , v_row.sub_infinite_time_partitions
        , v_row.sub_jobmon
        , v_row.sub_template_table
        , v_row.sub_inherit_privileges
        , v_row.sub_constraint_valid
        , v_row.sub_date_trunc_interval
        , v_row.sub_ignore_default_data);

    -- Set this equal to sibling configs so that newly created child table
    -- privileges are set properly below during initial setup.
    -- This setting is special because it applies immediately to the new child
    -- tables of a given parent, not just during maintenance like most other settings.
    v_inherit_privileges = v_row.sub_inherit_privileges;
END LOOP;

IF v_control_type = 'time' OR (v_control_type = 'id' AND p_epoch <> 'none') THEN

    v_time_interval := p_interval::interval;
    IF v_time_interval < '1 second'::interval THEN
        RAISE EXCEPTION 'Partitioning interval must be 1 second or greater';
    END IF;

   -- First partition is either the min premake or p_start_partition
    v_start_time := COALESCE(p_start_partition::timestamptz, CURRENT_TIMESTAMP - (v_time_interval * p_premake));

    SELECT base_timestamp, datetime_string
    INTO v_base_timestamp, v_datetime_string
    FROM @extschema@.calculate_time_partition_info(v_time_interval, v_start_time, p_date_trunc_interval);

    RAISE DEBUG 'create_parent(): parent_table: %, v_base_timestamp: %', p_parent_table, v_base_timestamp;

    v_partition_time_array := array_append(v_partition_time_array, v_base_timestamp);
    LOOP
        -- If current loop value is less than or equal to the value of the max premake, add time to array.
        IF (v_base_timestamp + (v_time_interval * v_count)) < (CURRENT_TIMESTAMP + (v_time_interval * p_premake)) THEN
            BEGIN
                v_partition_time := (v_base_timestamp + (v_time_interval * v_count))::timestamptz;
                v_partition_time_array := array_append(v_partition_time_array, v_partition_time);
            EXCEPTION WHEN datetime_field_overflow THEN
                RAISE WARNING 'Attempted partition time interval is outside PostgreSQL''s supported time range.
                    Child partition creation after time % skipped', v_partition_time;
                v_step_overflow_id := add_step(v_job_id, 'Attempted partition time interval is outside PostgreSQL''s supported time range.');
                PERFORM update_step(v_step_overflow_id, 'CRITICAL', 'Child partition creation after time '||v_partition_time||' skipped');
                CONTINUE;
            END;
        ELSE
            EXIT; -- all needed partitions added to array. Exit the loop.
        END IF;
        v_count := v_count + 1;
    END LOOP;

    INSERT INTO @extschema@.part_config (
        parent_table
        , partition_type
        , partition_interval
        , epoch
        , control
        , premake
        , constraint_cols
        , datetime_string
        , automatic_maintenance
        , jobmon
        , template_table
        , inherit_privileges
        , default_table
        , date_trunc_interval)
    VALUES (
        p_parent_table
        , p_type
        , v_time_interval
        , p_epoch
        , p_control
        , p_premake
        , p_constraint_cols
        , v_datetime_string
        , p_automatic_maintenance
        , p_jobmon
        , v_template_schema||'.'||v_template_tablename
        , v_inherit_privileges
        , p_default_table
        , p_date_trunc_interval);

    RAISE DEBUG 'create_parent: v_partition_time_array: %', v_partition_time_array;

    v_last_partition_created := @extschema@.create_partition_time(p_parent_table, v_partition_time_array);

    IF v_last_partition_created = false THEN
        -- This can happen with subpartitioning when future or past partitions prevent child creation because they're out of range of the parent
        -- First see if this parent is a subpartition managed by pg_partman
        WITH top_oid AS (
            SELECT i.inhparent AS top_parent_oid
            FROM pg_catalog.pg_inherits i
            JOIN pg_catalog.pg_class c ON c.oid = i.inhrelid
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relname = v_parent_tablename::name
            AND n.nspname = v_parent_schema::name
        ) SELECT n.nspname, c.relname
        INTO v_top_parent_schema, v_top_parent_table
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        JOIN top_oid t ON c.oid = t.top_parent_oid
        JOIN @extschema@.part_config p ON p.parent_table = n.nspname||'.'||c.relname;

        IF v_top_parent_table IS NOT NULL THEN
            -- If so create the lowest possible partition that is within the boundary of the parent
            SELECT child_start_time INTO v_parent_partition_timestamp FROM @extschema@.show_partition_info(p_parent_table, p_parent_table := v_top_parent_schema||'.'||v_top_parent_table);
            IF v_base_timestamp >= v_parent_partition_timestamp THEN
                WHILE v_base_timestamp >= v_parent_partition_timestamp LOOP
                    v_base_timestamp := v_base_timestamp - v_time_interval;
                END LOOP;
                v_base_timestamp := v_base_timestamp + v_time_interval; -- add one back since while loop set it one lower than is needed
            ELSIF v_base_timestamp < v_parent_partition_timestamp THEN
                WHILE v_base_timestamp < v_parent_partition_timestamp LOOP
                    v_base_timestamp := v_base_timestamp + v_time_interval;
                END LOOP;
                -- Don't need to remove one since new starting time will fit in top parent interval
            END IF;
            v_partition_time_array := NULL;
            v_partition_time_array := array_append(v_partition_time_array, v_base_timestamp);
            v_last_partition_created := @extschema@.create_partition_time(p_parent_table, v_partition_time_array);
        ELSE
            RAISE WARNING 'No child tables created. Check that all child tables did not already exist and may not have been part of partition set. Given parent has still been configured with pg_partman, but may not have expected children. Please review schema and config to confirm things are ok.';

            IF v_jobmon_schema IS NOT NULL THEN
                PERFORM update_step(v_step_id, 'OK', 'Done');
                IF v_step_overflow_id IS NOT NULL THEN
                    PERFORM fail_job(v_job_id);
                ELSE
                    PERFORM close_job(v_job_id);
                END IF;
            END IF;

            EXECUTE format('SELECT set_config(%L, %L, %L)', 'search_path', v_old_search_path, 'false');

            RETURN v_success;
        END IF;
    END IF; -- End v_last_partition IF

    IF v_jobmon_schema IS NOT NULL THEN
        PERFORM update_step(v_step_id, 'OK', format('Time partitions premade: %s', p_premake));
    END IF;

END IF;

IF v_control_type = 'id' AND p_epoch = 'none' THEN
    v_id_interval := p_interval::bigint;
    -- TODO: When list partitioning is supported, do not support interval less than 2 for ranged
    -- IF v_id_interval < 2 THEN
    --    RAISE EXCEPTION 'Interval for range partitioning must be greater than or equal to 2. Use LIST partitioning for single value partitions.';
    -- END IF;

    -- Check if parent table is a subpartition of an already existing id partition set managed by pg_partman.
    WHILE v_higher_parent_table IS NOT NULL LOOP -- initially set in DECLARE
        WITH top_oid AS (
            SELECT i.inhparent AS top_parent_oid
            FROM pg_catalog.pg_inherits i
            JOIN pg_catalog.pg_class c ON c.oid = i.inhrelid
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = v_higher_parent_schema::name
            AND c.relname = v_higher_parent_table::name
        ) SELECT n.nspname, c.relname, p.control, p.epoch
        INTO v_higher_parent_schema, v_higher_parent_table, v_higher_parent_control, v_higher_parent_epoch
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        JOIN top_oid t ON c.oid = t.top_parent_oid
        JOIN @extschema@.part_config p ON p.parent_table = n.nspname||'.'||c.relname;

        IF v_higher_parent_table IS NOT NULL THEN
            SELECT general_type INTO v_higher_control_type
            FROM @extschema@.check_control_type(v_higher_parent_schema, v_higher_parent_table, v_higher_parent_control);
            IF v_higher_control_type <> 'id' or (v_higher_control_type = 'id' AND v_higher_parent_epoch <> 'none') THEN
                -- The parent above the p_parent_table parameter is not partitioned by ID
                --   so don't check for max values in parents that aren't partitioned by ID.
                -- This avoids missing child tables in subpartition sets that have differing ID data
                EXIT;
            END IF;
            -- v_top_parent initially set in DECLARE
            v_top_parent_schema := v_higher_parent_schema;
            v_top_parent_table := v_higher_parent_table;
        END IF;
    END LOOP;

    -- If custom start partition is set, use that.
    -- If custom start is not set and there is already data, start partitioning with the highest current value and ensure it's grabbed from highest top parent table
    IF p_start_partition IS NOT NULL THEN
        v_max := p_start_partition::bigint;
    ELSE
        v_sql := format('SELECT COALESCE(max(%I)::bigint, 0) FROM %I.%I LIMIT 1'
                    , p_control
                    , v_top_parent_schema
                    , v_top_parent_table);
        EXECUTE v_sql INTO v_max;
    END IF;

    v_starting_partition_id := v_max - (v_max % v_id_interval);
    FOR i IN 0..p_premake LOOP
        -- Only make previous partitions if ID value is less than the starting value and positive (and custom start partition wasn't set)
        IF p_start_partition IS NULL AND
            (v_starting_partition_id - (v_id_interval*i)) > 0 AND
            (v_starting_partition_id - (v_id_interval*i)) < v_starting_partition_id
        THEN
            v_partition_id_array = array_append(v_partition_id_array, (v_starting_partition_id - v_id_interval*i));
        END IF;
        v_partition_id_array = array_append(v_partition_id_array, (v_id_interval*i) + v_starting_partition_id);
    END LOOP;

    INSERT INTO @extschema@.part_config (
        parent_table
        , partition_type
        , partition_interval
        , control
        , premake
        , constraint_cols
        , automatic_maintenance
        , jobmon
        , template_table
        , inherit_privileges
        , default_table
        , date_trunc_interval)
    VALUES (
        p_parent_table
        , p_type
        , v_id_interval
        , p_control
        , p_premake
        , p_constraint_cols
        , p_automatic_maintenance
        , p_jobmon
        , v_template_schema||'.'||v_template_tablename
        , v_inherit_privileges
        , p_default_table
        , p_date_trunc_interval);

    v_last_partition_created := @extschema@.create_partition_id(p_parent_table, v_partition_id_array);

    IF v_last_partition_created = false THEN
        -- This can happen with subpartitioning when future or past partitions prevent child creation because they're out of range of the parent
        -- See if it's actually a subpartition of a parent id partition
        WITH top_oid AS (
            SELECT i.inhparent AS top_parent_oid
            FROM pg_catalog.pg_inherits i
            JOIN pg_catalog.pg_class c ON c.oid = i.inhrelid
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relname = v_parent_tablename::name
            AND n.nspname = v_parent_schema::name
        ) SELECT n.nspname||'.'||c.relname
        INTO v_top_parent_table
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        JOIN top_oid t ON c.oid = t.top_parent_oid
        JOIN @extschema@.part_config p ON p.parent_table = n.nspname||'.'||c.relname;

        IF v_top_parent_table IS NOT NULL THEN
            -- Create the lowest possible partition that is within the boundary of the parent
             SELECT child_start_id INTO v_parent_partition_id FROM @extschema@.show_partition_info(p_parent_table, p_parent_table := v_top_parent_table);
            IF v_starting_partition_id >= v_parent_partition_id THEN
                WHILE v_starting_partition_id >= v_parent_partition_id LOOP
                    v_starting_partition_id := v_starting_partition_id - v_id_interval;
                END LOOP;
                v_starting_partition_id := v_starting_partition_id + v_id_interval; -- add one back since while loop set it one lower than is needed
            ELSIF v_starting_partition_id < v_parent_partition_id THEN
                WHILE v_starting_partition_id < v_parent_partition_id LOOP
                    v_starting_partition_id := v_starting_partition_id + v_id_interval;
                END LOOP;
                -- Don't need to remove one since new starting id will fit in top parent interval
            END IF;
            v_partition_id_array = NULL;
            v_partition_id_array = array_append(v_partition_id_array, v_starting_partition_id);
            v_last_partition_created := @extschema@.create_partition_id(p_parent_table, v_partition_id_array);
        ELSE
            -- Currently unknown edge case if code gets here
            RAISE WARNING 'No child tables created. Check that all child tables did not already exist and may not have been part of partition set. Given parent has still been configured with pg_partman, but may not have expected children. Please review schema and config to confirm things are ok.';
            IF v_jobmon_schema IS NOT NULL THEN
                PERFORM update_step(v_step_id, 'OK', 'Done');
                IF v_step_overflow_id IS NOT NULL THEN
                    PERFORM fail_job(v_job_id);
                ELSE
                    PERFORM close_job(v_job_id);
                END IF;
            END IF;

            EXECUTE format('SELECT set_config(%L, %L, %L)', 'search_path', v_old_search_path, 'false');

            RETURN v_success;
        END IF;
    END IF; -- End v_last_partition_created IF

END IF; -- End IF id

IF p_default_table THEN
    -- Add default partition

    v_default_partition := @extschema@.check_name_length(v_parent_tablename, '_default', FALSE);
    v_sql := 'CREATE';

    -- Left this here as reminder to revisit once core PG figures out how it is handling changing unlogged stats
    -- Currently handed via template table below
    /*
    IF v_unlogged = 'u' THEN
         v_sql := v_sql ||' UNLOGGED';
    END IF;
    */

    -- Same INCLUDING list is used in create_partition_*(). INDEXES is handled when partition is attached if it's supported.
    v_sql := v_sql || format(' TABLE %I.%I (LIKE %I.%I INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING STORAGE INCLUDING COMMENTS INCLUDING GENERATED)'
        , v_parent_schema, v_default_partition, v_parent_schema, v_parent_tablename);
    EXECUTE v_sql;

    v_sql := format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I DEFAULT'
        , v_parent_schema, v_parent_tablename, v_parent_schema, v_default_partition);
    EXECUTE v_sql;

    -- Manage template inherited properties
    PERFORM @extschema@.inherit_template_properties(p_parent_table, v_parent_schema, v_default_partition);

END IF;


IF v_jobmon_schema IS NOT NULL THEN
    PERFORM update_step(v_step_id, 'OK', 'Done');
    IF v_step_overflow_id IS NOT NULL THEN
        PERFORM fail_job(v_job_id);
    ELSE
        PERFORM close_job(v_job_id);
    END IF;
END IF;

EXECUTE format('SELECT set_config(%L, %L, %L)', 'search_path', v_old_search_path, 'false');

v_success := true;

RETURN v_success;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS ex_message = MESSAGE_TEXT,
                                ex_context = PG_EXCEPTION_CONTEXT,
                                ex_detail = PG_EXCEPTION_DETAIL,
                                ex_hint = PG_EXCEPTION_HINT;
        IF v_jobmon_schema IS NOT NULL THEN
            IF v_job_id IS NULL THEN
                EXECUTE format('SELECT %I.add_job(''PARTMAN CREATE PARENT: %s'')', v_jobmon_schema, p_parent_table) INTO v_job_id;
                EXECUTE format('SELECT %I.add_step(%s, ''Partition creation for table '||p_parent_table||' failed'')', v_jobmon_schema, v_job_id, p_parent_table) INTO v_step_id;
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
