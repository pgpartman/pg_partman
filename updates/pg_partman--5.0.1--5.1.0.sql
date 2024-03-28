-- SEE CHANGELOG.md for all notes and details on this update

CREATE TEMP TABLE partman_preserve_privs_temp (statement text);

INSERT INTO partman_preserve_privs_temp
SELECT 'GRANT EXECUTE ON FUNCTION @extschema@.check_subpart_sameconfig(text) TO '||array_to_string(array_agg('"'||grantee::text||'"'), ',')||';'
FROM information_schema.routine_privileges
WHERE routine_schema = '@extschema@'
AND routine_name = 'check_subpart_sameconfig'
AND grantee != 'PUBLIC';

INSERT INTO partman_preserve_privs_temp
SELECT 'GRANT EXECUTE ON FUNCTION @extschema@.partition_gap_fill(text) TO '||array_to_string(array_agg('"'||grantee::text||'"'), ',')||';'
FROM information_schema.routine_privileges
WHERE routine_schema = '@extschema@'
AND routine_name = 'partition_gap_fill'
AND grantee != 'PUBLIC';

DROP FUNCTION @extschema@.check_subpart_sameconfig(text);

-- Drop both function signatures to handle edge cases around upgrading from any 4.x version or 5.0
DROP FUNCTION IF EXISTS @extschema@.partition_gap_fill(text, boolean);
DROP FUNCTION IF EXISTS @extschema@.partition_gap_fill(text);

ALTER TABLE @extschema@.part_config ADD COLUMN maintenance_order int DEFAULT NULL;
ALTER TABLE @extschema@.part_config_sub ADD COLUMN sub_maintenance_order int DEFAULT NULL;
ALTER TABLE @extschema@.part_config ADD COLUMN retention_keep_publication boolean NOT NULL DEFAULT false;
ALTER TABLE @extschema@.part_config_sub ADD COLUMN sub_retention_keep_publication boolean NOT NULL DEFAULT false;
ALTER TABLE @extschema@.part_config ADD COLUMN maintenance_last_run timestamptz;

CREATE OR REPLACE FUNCTION @extschema@.create_parent(
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
v_parent_tablespace             name;
v_part_col                      text;
v_part_type                     text;
v_partattrs                     smallint[];
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

SELECT n.nspname
    , c.relname
    , c.relpersistence
    , t.spcname
INTO v_parent_schema
    , v_parent_tablename
    , v_unlogged
    , v_parent_tablespace
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
LEFT OUTER JOIN pg_catalog.pg_tablespace t ON c.reltablespace = t.oid
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
    RAISE EXCEPTION 'pg_partman only supports partitioning of data types that are integer, numeric or date/timestamp. Supplied column is of type %', v_control_exact_type;
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
-- Check if given parent table has been already set up as a partitioned table
SELECT p.partstrat
    , p.partattrs
INTO v_partstrat
    , v_partattrs
FROM pg_catalog.pg_partitioned_table p
JOIN pg_catalog.pg_class c ON p.partrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = v_parent_schema::name
AND c.relname = v_parent_tablename::name;

IF v_partstrat NOT IN ('r', 'l') OR v_partstrat IS NULL THEN
    RAISE EXCEPTION 'You must have created the given parent table as ranged or list partitioned already. Ex: CREATE TABLE ... PARTITION BY [RANGE|LIST] ...)';
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
        , a.sub_retention_keep_publication
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
        , sub_ignore_default_data
        , sub_retention_keep_publication)
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
        , v_row.sub_ignore_default_data
        , v_row.sub_retention_keep_publication);

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
    IF v_id_interval < 2 AND p_type != 'list' THEN
       RAISE EXCEPTION 'Interval for range partitioning must be greater than or equal to 2. Use LIST partitioning for single value partitions. (Values given: p_interval: %, p_type: %)', p_interval, p_type;
    END IF;

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
        v_sql := format('SELECT COALESCE(trunc(max(%I))::bigint, 0) FROM %I.%I LIMIT 1'
                    , p_control
                    , v_top_parent_schema
                    , v_top_parent_table);
        EXECUTE v_sql INTO v_max;
    END IF;

    v_starting_partition_id := (v_max - (v_max % v_id_interval));
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
    IF v_parent_tablespace IS NOT NULL THEN
        v_sql := format('%s TABLESPACE %I ', v_sql, v_parent_tablespace);
    END IF;
    EXECUTE v_sql;

    v_sql := format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I DEFAULT'
        , v_parent_schema, v_parent_tablename, v_parent_schema, v_default_partition);
    EXECUTE v_sql;

    PERFORM @extschema@.inherit_replica_identity(v_parent_schema, v_parent_tablename, v_default_partition);

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


CREATE FUNCTION @extschema@.check_subpart_sameconfig(p_parent_table text)
    RETURNS TABLE (
         sub_control text
        , sub_partition_interval text
        , sub_partition_type text
        , sub_premake int
        , sub_automatic_maintenance text
        , sub_template_table text
        , sub_retention text
        , sub_retention_schema text
        , sub_retention_keep_index boolean
        , sub_retention_keep_table boolean
        , sub_epoch text
        , sub_constraint_cols text[]
        , sub_optimize_constraint int
        , sub_infinite_time_partitions boolean
        , sub_jobmon boolean
        , sub_inherit_privileges boolean
        , sub_constraint_valid boolean
        , sub_date_trunc_interval text
        , sub_ignore_default_data boolean
        , sub_default_table boolean
        , sub_maintenance_order int
        , sub_retention_keep_publication boolean
        )
    LANGUAGE sql STABLE
    SET search_path = @extschema@,pg_temp
AS $$
/*
 * Check for consistent data in part_config_sub table. Was unable to get this working properly as either a constraint or trigger.
 * Would either delay raising an error until the next write (which I cannot predict) or disallow future edits to update a sub-partition set's configuration.
 * This is called by run_maintainance() and at least provides a consistent way to check that I know will run.
 * If anyone can get a working constraint/trigger, please help!
*/

    WITH parent_info AS (
        SELECT c1.oid
        FROM pg_catalog.pg_class c1
        JOIN pg_catalog.pg_namespace n1 ON c1.relnamespace = n1.oid
        WHERE n1.nspname = split_part(p_parent_table, '.', 1)::name
        AND c1.relname = split_part(p_parent_table, '.', 2)::name
    )
    , child_tables AS (
        SELECT n.nspname||'.'||c.relname AS tablename
        FROM pg_catalog.pg_inherits h
        JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        JOIN parent_info pi ON h.inhparent = pi.oid
    )
    -- Column order here must match the RETURNS TABLE definition
    -- This column list must be kept consistent between:
    --   create_parent, check_subpart_sameconfig, create_partition_id, create_partition_time, dump_partitioned_table_definition, and table definition
    --   Also check return table list from this function
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
        , a.sub_maintenance_order
        , a.sub_retention_keep_publication
    FROM @extschema@.part_config_sub a
    JOIN child_tables b on a.sub_parent = b.tablename;
$$;


CREATE OR REPLACE FUNCTION @extschema@.create_partition_id(
    p_parent_table text
    , p_partition_ids bigint[]
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
v_exists                        text;
v_id                            bigint;
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
v_partition_interval            bigint;
v_partition_created             boolean := false;
v_partition_name                text;
v_partition_type                text;
v_row                           record;
v_sql                           text;
v_step_id                       bigint;
v_sub_control                   text;
v_sub_partition_type            text;
v_sub_id_max                    bigint;
v_sub_id_min                    bigint;
v_template_table                text;

BEGIN
/*
 * Function to create id partitions
 */

SELECT control
    , partition_interval::bigint -- this shared field also used in partition_time as interval
    , partition_type
    , jobmon
    , template_table
    , inherit_privileges
INTO v_control
    , v_partition_interval
    , v_partition_type
    , v_jobmon
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
IF v_control_type <> 'id' THEN
    RAISE EXCEPTION 'ERROR: Given parent table is not set up for id/serial partitioning';
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
SELECT sub_min::bigint, sub_max::bigint INTO v_sub_id_min, v_sub_id_max FROM @extschema@.check_subpartition_limits(p_parent_table, 'id');

IF v_jobmon_schema IS NOT NULL THEN
    v_job_id := add_job(format('PARTMAN CREATE TABLE: %s', p_parent_table));
END IF;

FOREACH v_id IN ARRAY p_partition_ids LOOP
-- Do not create the child table if it's outside the bounds of the top parent.
    IF v_sub_id_min IS NOT NULL THEN
        IF v_id < v_sub_id_min OR v_id >= v_sub_id_max THEN
            CONTINUE;
        END IF;
    END IF;

    v_partition_name := @extschema@.check_name_length(v_parent_tablename, v_id::text, TRUE);
    -- If child table already exists, skip creation
    -- Have to check pg_class because if subpartitioned, table will not be in pg_tables
    SELECT c.relname INTO v_exists
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = v_parent_schema::name AND c.relname = v_partition_name::name;
    IF v_exists IS NOT NULL THEN
        CONTINUE;
    END IF;

    IF v_jobmon_schema IS NOT NULL THEN
        v_step_id := add_step(v_job_id, 'Creating new partition '||v_partition_name||' with interval from '||v_id||' to '||(v_id + v_partition_interval)-1);
    END IF;

    -- Close parentheses on LIKE are below due to differing requirements of subpartitioning
    -- Same INCLUDING list is used in create_parent()
    v_sql := format('CREATE TABLE %I.%I (LIKE %I.%I INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING STORAGE INCLUDING COMMENTS INCLUDING GENERATED) '
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
    ELSIF v_sub_partition_type = 'list' THEN
        v_sql :=  format('%s PARTITION BY LIST (%I) ', v_sql, v_sub_control);
    END IF;

    RAISE DEBUG 'create_partition_id v_sql: %', v_sql;
    EXECUTE v_sql;

    IF v_template_table IS NOT NULL THEN
        PERFORM @extschema@.inherit_template_properties(p_parent_table, v_parent_schema, v_partition_name);
    END IF;

    IF v_partition_type = 'range' THEN
        EXECUTE format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I FOR VALUES FROM (%L) TO (%L)'
            , v_parent_schema
            , v_parent_tablename
            , v_parent_schema
            , v_partition_name
            , v_id
            , v_id + v_partition_interval);
    ELSIF v_partition_type = 'list' THEN
        EXECUTE format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I FOR VALUES IN (%L)'
            , v_parent_schema
            , v_parent_tablename
            , v_parent_schema
            , v_partition_name
            , v_id);
    ELSE
        RAISE EXCEPTION 'create_partition_id: Unexpected partition type (%) encountered in part_config table for parent table %', v_partition_type, p_parent_table;
    END IF;

    -- NOTE: Privileges not automatically inherited. Only do so if config flag is set
    IF v_inherit_privileges = TRUE THEN
        PERFORM @extschema@.apply_privileges(v_parent_schema, v_parent_tablename, v_parent_schema, v_partition_name, v_job_id);
    END IF;

    IF v_jobmon_schema IS NOT NULL THEN
        PERFORM update_step(v_step_id, 'OK', 'Done');
    END IF;

    -- Will only loop once and only if sub_partitioning is actually configured
    -- This seemed easier than assigning a bunch of variables then doing an IF condition
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
            v_step_id := add_step(v_job_id, 'Subpartitioning '||v_partition_name);
        END IF;
        v_sql := format('SELECT @extschema@.create_parent(
                 p_parent_table := %L
                , p_control := %L
                , p_type := %L
                , p_interval := %L
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
            , v_row.sub_partition_type
            , v_row.sub_partition_interval
            , v_row.sub_default_table
            , v_row.sub_constraint_cols
            , v_row.sub_premake
            , v_row.sub_automatic_maintenance
            , v_row.sub_epoch
            , v_row.sub_template_table
            , v_row.sub_jobmon
            , p_start_partition
            , v_row.sub_date_trunc_interval);
        RAISE DEBUG 'create_partition_id (create_parent loop): %', v_sql;
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

        IF v_jobmon_schema IS NOT NULL THEN
            PERFORM update_step(v_step_id, 'OK', 'Done');
        END IF;

    END LOOP; -- end sub partitioning LOOP

    -- NOTE: Replication identity not automatically inherited as of PG16 (revisit in future versions)
    PERFORM @extschema@.inherit_replica_identity(v_parent_schema, v_parent_tablename, v_partition_name);

    -- Manage additional constraints if set
    PERFORM @extschema@.apply_constraints(p_parent_table, p_job_id := v_job_id);

    v_partition_created := true;

END LOOP;

IF v_jobmon_schema IS NOT NULL THEN
    IF v_partition_created = false THEN
        v_step_id := add_step(v_job_id, format('No partitions created for partition set: %s', p_parent_table));
        PERFORM update_step(v_step_id, 'OK', 'Done');
    END IF;

    PERFORM close_job(v_job_id);
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


CREATE OR REPLACE FUNCTION @extschema@.create_partition_time(
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


CREATE OR REPLACE FUNCTION @extschema@.dump_partitioned_table_definition(
    p_parent_table text,
    p_ignore_template_table boolean DEFAULT false
)
    RETURNS text
    LANGUAGE PLPGSQL STABLE
    AS $$
DECLARE
    v_create_parent_definition text;
    v_update_part_config_definition text;
    -- Columns from part_config table.
    v_parent_table text; -- NOT NULL
    v_control text; -- NOT NULL
    v_partition_type text; -- NOT NULL
    v_partition_interval text; -- NOT NULL
    v_constraint_cols TEXT[];
    v_premake integer; -- NOT NULL
    v_optimize_constraint integer; -- NOT NULL
    v_epoch text; -- NOT NULL
    v_retention text;
    v_retention_schema text;
    v_retention_keep_index boolean;
    v_retention_keep_table boolean; -- NOT NULL
    v_infinite_time_partitions boolean; -- NOT NULL
    v_datetime_string text;
    v_automatic_maintenance text; -- NOT NULL
    v_jobmon boolean; -- NOT NULL
    v_sub_partition_set_full boolean; -- NOT NULL
    v_template_table text;
    v_inherit_privileges boolean; -- DEFAULT false
    v_constraint_valid boolean; -- DEFAULT true NOT NULL
    v_ignore_default_data boolean; -- DEFAULT false NOT NULL
    v_date_trunc_interval text;
    v_default_table boolean;
    v_maintenance_order int;
    v_retention_keep_publication boolean;
BEGIN
    SELECT
        pc.parent_table,
        pc.control,
        pc.partition_type,
        pc.partition_interval,
        pc.constraint_cols,
        pc.premake,
        pc.optimize_constraint,
        pc.epoch,
        pc.retention,
        pc.retention_schema,
        pc.retention_keep_index,
        pc.retention_keep_table,
        pc.infinite_time_partitions,
        pc.datetime_string,
        pc.automatic_maintenance,
        pc.jobmon,
        pc.sub_partition_set_full,
        pc.template_table,
        pc.inherit_privileges,
        pc.constraint_valid,
        pc.ignore_default_data,
        pc.date_trunc_interval,
        pc.default_table,
        pc.maintenance_order,
        pc.retention_keep_publication
    INTO
        v_parent_table,
        v_control,
        v_partition_type,
        v_partition_interval,
        v_constraint_cols,
        v_premake,
        v_optimize_constraint,
        v_epoch,
        v_retention,
        v_retention_schema,
        v_retention_keep_index,
        v_retention_keep_table,
        v_infinite_time_partitions,
        v_datetime_string,
        v_automatic_maintenance,
        v_jobmon,
        v_sub_partition_set_full,
        v_template_table,
        v_inherit_privileges,
        v_constraint_valid,
        v_ignore_default_data,
        v_date_trunc_interval,
        v_default_table,
        v_maintenance_order,
        v_retention_keep_publication
    FROM @extschema@.part_config pc
    WHERE pc.parent_table = p_parent_table;

    IF v_parent_table IS NULL THEN
        RAISE EXCEPTION 'Given parent table not found in pg_partman configuration table: %', p_parent_table;
    END IF;

    IF p_ignore_template_table THEN
        v_template_table := NULL;
    END IF;

    v_create_parent_definition := format(
E'SELECT @extschema@.create_parent(
\tp_parent_table := %L,
\tp_control := %L,
\tp_interval := %L,
\tp_type := %L,
\tp_epoch := %L,
\tp_premake := %s,
\tp_default_table := %L,
\tp_automatic_maintenance := %L,
\tp_constraint_cols := %L,
\tp_template_table := %L,
\tp_jobmon := %L,
\tp_date_trunc_interval := %L
);',
            v_parent_table,
            v_control,
            v_partition_interval,
            v_partition_type,
            v_epoch,
            v_premake,
            v_default_table,
            v_automatic_maintenance,
            v_constraint_cols,
            v_template_table,
            v_jobmon,
            v_date_trunc_interval
        );

    v_update_part_config_definition := format(
E'UPDATE @extschema@.part_config SET
\toptimize_constraint = %s,
\tretention = %L,
\tretention_schema = %L,
\tretention_keep_index = %L,
\tretention_keep_table = %L,
\tinfinite_time_partitions = %L,
\tdatetime_string = %L,
\tsub_partition_set_full = %L,
\tinherit_privileges = %L,
\tconstraint_valid = %L,
\tignore_default_data = %L,
\tmaintenance_order = %L,
\tretention_keep_publication = %L
WHERE parent_table = %L;',
        v_optimize_constraint,
        v_retention,
        v_retention_schema,
        v_retention_keep_index,
        v_retention_keep_table,
        v_infinite_time_partitions,
        v_datetime_string,
        v_sub_partition_set_full,
        v_inherit_privileges,
        v_constraint_valid,
        v_ignore_default_data,
        v_maintenance_order,
        v_retention_keep_publication,
        v_parent_table
    );

    RETURN concat_ws(E'\n',
        v_create_parent_definition,
        v_update_part_config_definition
    );
END
$$;


CREATE OR REPLACE FUNCTION @extschema@.inherit_template_properties(
    p_parent_table text
    , p_child_schema text
    , p_child_tablename text
)
    RETURNS boolean
    LANGUAGE plpgsql
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

BEGIN
/*
 * Function to inherit the properties of the template table to newly created child tables.
 * For PG14+, used to inherit non-partition-key unique indexes & primary keys and unlogged status
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
            v_sql := v_sql || format(' TABLESPACE %I', v_index_list.tablespace_name);
        END IF;

        RAISE DEBUG 'inherit_template_properties: Create index: %', v_sql;
        EXECUTE v_sql;
    ELSE
        RAISE EXCEPTION 'inherit_template_properties: Unexpected code path in unique index creation. Please report the steps that lead to this error to extension maintainers.';
    END IF;

END LOOP;
-- End index creation

-- UNLOGGED status. Currently waiting on final stance of how upstream will handle this property being changed for its children.
-- See release notes for v4.2.0
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
RETURN true;

END
$$;



CREATE OR REPLACE FUNCTION @extschema@.run_maintenance(
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


CREATE OR REPLACE PROCEDURE @extschema@.run_maintenance_proc(
    p_wait int DEFAULT 0
    -- Keep these defaults in sync with `run_maintenance`!
    , p_analyze boolean DEFAULT false
    , p_jobmon boolean DEFAULT true
)
    LANGUAGE plpgsql
    AS $$
DECLARE

v_adv_lock              boolean;
v_parent_table          text;
v_sql                   text;

BEGIN

v_adv_lock := pg_try_advisory_lock(hashtext('pg_partman run_maintenance procedure'));
IF v_adv_lock = false THEN
    RAISE NOTICE 'Partman maintenance procedure already running or another session has not released its advisory lock.';
    RETURN;
END IF;

IF pg_is_in_recovery() THEN
    RAISE DEBUG 'pg_partmain maintenance procedure called on replica. Doing nothing.';
    RETURN;
END IF;

FOR v_parent_table IN
    SELECT parent_table
    FROM @extschema@.part_config
    WHERE undo_in_progress = false
    AND automatic_maintenance = 'on'
    ORDER BY maintenance_order ASC NULLS LAST
LOOP
/*
 * Run maintenance with a commit between each partition set
 */
    v_sql := format('SELECT %s.run_maintenance(%L, p_jobmon := %L',
        '@extschema@', v_parent_table, p_jobmon);

    IF p_analyze IS NOT NULL THEN
        v_sql := v_sql || format(', p_analyze := %L', p_analyze);
    END IF;

    v_sql := v_sql || ')';

    RAISE DEBUG 'v_sql run_maintenance_proc: %', v_sql;

    EXECUTE v_sql;
    COMMIT;

    PERFORM pg_sleep(p_wait);

END LOOP;

PERFORM pg_advisory_unlock(hashtext('pg_partman run_maintenance procedure'));
END
$$;


CREATE OR REPLACE FUNCTION @extschema@.check_control_type(p_parent_schema text, p_parent_tablename text, p_control text) RETURNS TABLE (general_type text, exact_type text)
    LANGUAGE sql STABLE
AS $$
/*
 * Return column type for given table & column in that table
 * Returns NULL if objects don't match compatible types
 */

SELECT CASE
        WHEN typname IN ('timestamptz', 'timestamp', 'date') THEN
            'time'
        WHEN typname IN ('int2', 'int4', 'int8', 'numeric' ) THEN
            'id'
       END
    , typname::text
    FROM pg_catalog.pg_type t
    JOIN pg_catalog.pg_attribute a ON t.oid = a.atttypid
    JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = p_parent_schema::name
    AND c.relname = p_parent_tablename::name
    AND a.attname = p_control::name
$$;


CREATE OR REPLACE FUNCTION @extschema@.show_partitions (
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


CREATE OR REPLACE FUNCTION @extschema@.show_partition_info(
    p_child_table text
    , p_partition_interval text DEFAULT NULL
    , p_parent_table text DEFAULT NULL
    , OUT child_start_time timestamptz
    , OUT child_end_time timestamptz
    , OUT child_start_id bigint
    , OUT child_end_id bigint
    , OUT suffix text
)
    RETURNS record
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE

v_child_schema          text;
v_child_tablename       text;
v_control               text;
v_control_type          text;
v_epoch                 text;
v_exact_control_type    text;
v_parent_table          text;
v_partstrat             char;
v_partition_interval    text;
v_start_string          text;

BEGIN
/*
 * Show the data boundaries for a given child table as well as the suffix that will be used.
 * Passing the parent table argument slightly improves performance by avoiding a catalog lookup.
 * Passing an interval lets you set one different than the default configured one if desired.
 */

SELECT n.nspname, c.relname INTO v_child_schema, v_child_tablename
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_child_table, '.', 1)::name
AND c.relname = split_part(p_child_table, '.', 2)::name;

IF v_child_tablename IS NULL THEN
    IF p_parent_table IS NOT NULL THEN
        RAISE EXCEPTION 'Child table given does not exist (%) for given parent table (%)', p_child_table, p_parent_table;
    ELSE
        RAISE EXCEPTION 'Child table given does not exist (%)', p_child_table;
    END IF;
END IF;

IF p_parent_table IS NULL THEN
    SELECT n.nspname||'.'|| c.relname INTO v_parent_table
    FROM pg_catalog.pg_inherits h
    JOIN pg_catalog.pg_class c ON c.oid = h.inhparent
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE h.inhrelid::regclass = p_child_table::regclass;
ELSE
    v_parent_table := p_parent_table;
END IF;

SELECT p.partstrat INTO v_partstrat
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
JOIN pg_catalog.pg_partitioned_table p ON c.oid = p.partrelid
WHERE n.nspname = split_part(v_parent_table, '.', 1)::name
AND c.relname = split_part(v_parent_table, '.', 2)::name;

IF p_partition_interval IS NULL THEN
    SELECT control, partition_interval, epoch
    INTO v_control, v_partition_interval, v_epoch
    FROM @extschema@.part_config WHERE parent_table = v_parent_table;
ELSE
    v_partition_interval := p_partition_interval;
    SELECT control, epoch
    INTO v_control, v_epoch
    FROM @extschema@.part_config WHERE parent_table = v_parent_table;
END IF;

IF v_control IS NULL THEN
    RAISE EXCEPTION 'Parent table of given child not managed by pg_partman: %', v_parent_table;
END IF;

SELECT general_type, exact_type INTO v_control_type, v_exact_control_type FROM @extschema@.check_control_type(v_child_schema, v_child_tablename, v_control);

RAISE DEBUG 'show_partition_info: v_child_schema: %, v_child_tablename: %, v_control_type: %, v_exact_control_type: %',
            v_child_schema, v_child_tablename, v_control_type, v_exact_control_type;

-- Look at actual partition bounds in catalog and pull values from there.
IF v_partstrat = 'r' THEN
    SELECT (regexp_match(pg_get_expr(c.relpartbound, c.oid, true)
        , $REGEX$\(([^)]+)\) TO \(([^)]+)\)$REGEX$))[1]::text
    INTO v_start_string
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relname = v_child_tablename
    AND n.nspname = v_child_schema;
ELSIF v_partstrat = 'l' THEN
    SELECT (regexp_match(pg_get_expr(c.relpartbound, c.oid, true)
        , $REGEX$FOR VALUES IN \(([^)])\)$REGEX$))[1]::text
    INTO v_start_string
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relname = v_child_tablename
    AND n.nspname = v_child_schema;
ELSE
    RAISE EXCEPTION 'partman functions only work with list partitioning with integers and ranged partitioning with time or integers. Found partition strategy "%" for given partition set', v_partstrat;
END IF;

IF v_control_type = 'time' OR (v_control_type = 'id' AND v_epoch <> 'none') THEN

    IF v_control_type = 'time' THEN
        child_start_time := v_start_string::timestamptz;
    ELSIF (v_control_type = 'id' AND v_epoch <> 'none') THEN
        -- bigint data type is stored as a single-quoted string in the partition expression. Must strip quotes for valid type-cast.
        v_start_string := trim(BOTH '''' FROM v_start_string);
        IF v_epoch = 'seconds' THEN
            child_start_time := to_timestamp(v_start_string::double precision);
        ELSIF v_epoch = 'milliseconds' THEN
            child_start_time := to_timestamp((v_start_string::double precision) / 1000);
        ELSIF v_epoch = 'nanoseconds' THEN
            child_start_time := to_timestamp((v_start_string::double precision) / 1000000000);
        END IF;
    ELSE
        RAISE EXCEPTION 'Unexpected code path in show_partition_info(). Please report this bug with the configuration that lead to it.';
    END IF;

    child_end_time := (child_start_time + v_partition_interval::interval);

    SELECT to_char(base_timestamp, datetime_string)
    INTO suffix
    FROM @extschema@.calculate_time_partition_info(v_partition_interval::interval, child_start_time);

ELSIF v_control_type = 'id' THEN

    IF v_exact_control_type IN ('int8', 'int4', 'int2') THEN
        child_start_id := trim(BOTH '''' FROM v_start_string)::bigint;
    ELSIF v_exact_control_type = 'numeric' THEN
        -- cast to numeric then trunc to get rid of decimal without rounding
        child_start_id := trunc(trim(BOTH '''' FROM v_start_string)::numeric)::bigint;
    END IF;

    child_end_id := (child_start_id + v_partition_interval::bigint) - 1;

ELSE
    RAISE EXCEPTION 'Invalid partition type encountered in show_partition_info()';
END IF;

RETURN;

END
$$;


CREATE OR REPLACE FUNCTION @extschema@.check_partition_type (p_type text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER
    SET search_path TO pg_catalog, pg_temp
    AS $$
DECLARE
v_result    boolean;
BEGIN
    SELECT p_type IN ('range', 'list') INTO v_result;
    RETURN v_result;
END
$$;


CREATE OR REPLACE FUNCTION @extschema@.drop_partition_id(
    p_parent_table text
    , p_retention bigint DEFAULT NULL
    , p_keep_table boolean DEFAULT NULL
    , p_keep_index boolean DEFAULT NULL
    , p_retention_schema text DEFAULT NULL
)
    RETURNS int
    LANGUAGE plpgsql
    AS $$
DECLARE

ex_context                          text;
ex_detail                           text;
ex_hint                             text;
ex_message                          text;
v_adv_lock                          boolean;
v_control                           text;
v_control_type                      text;
v_count                             int;
v_drop_count                        int := 0;
v_index                             record;
v_job_id                            bigint;
v_jobmon                            boolean;
v_jobmon_schema                     text;
v_max                               bigint;
v_new_search_path                   text;
v_old_search_path                   text;
v_parent_schema                     text;
v_parent_tablename                  text;
v_partition_interval                bigint;
v_partition_id                      bigint;
v_pubname_row                       record;
v_retention                         bigint;
v_retention_keep_index              boolean;
v_retention_keep_table              boolean;
v_retention_keep_publication        boolean;
v_retention_schema                  text;
v_row                               record;
v_row_max_id                        record;
v_sql                               text;
v_step_id                           bigint;
v_sub_parent                        text;

BEGIN
/*
 * Function to drop child tables from an id-based partition set.
 * Options to move table to different schema or actually drop the table from the database.
 */

v_adv_lock := pg_try_advisory_xact_lock(hashtext('pg_partman drop_partition_id'));
IF v_adv_lock = 'false' THEN
    RAISE NOTICE 'drop_partition_id already running.';
    RETURN 0;
END IF;

IF p_retention IS NULL THEN
    SELECT
        partition_interval::bigint
        , control
        , retention::bigint
        , retention_keep_table
        , retention_keep_index
        , retention_keep_publication
        , retention_schema
        , jobmon
    INTO
        v_partition_interval
        , v_control
        , v_retention
        , v_retention_keep_table
        , v_retention_keep_index
        , v_retention_keep_publication
        , v_retention_schema
        , v_jobmon
    FROM @extschema@.part_config
    WHERE parent_table = p_parent_table
    AND retention IS NOT NULL;

    IF v_partition_interval IS NULL THEN
        RAISE EXCEPTION 'Configuration for given parent table with a retention period not found: %', p_parent_table;
    END IF;
ELSE -- Allow override of configuration options
     SELECT
        partition_interval::bigint
        , control
        , retention_keep_table
        , retention_keep_index
        , retention_keep_publication
        , retention_schema
        , jobmon
    INTO
        v_partition_interval
        , v_control
        , v_retention_keep_table
        , v_retention_keep_index
        , v_retention_keep_publication
        , v_retention_schema
        , v_jobmon
    FROM @extschema@.part_config
    WHERE parent_table = p_parent_table;
    v_retention := p_retention;

    IF v_partition_interval IS NULL THEN
        RAISE EXCEPTION 'Configuration for given parent table not found: %', p_parent_table;
    END IF;
END IF;

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_parent_schema, v_parent_tablename, v_control);
IF v_control_type <> 'id' THEN
    RAISE EXCEPTION 'Data type of control column in given partition set is not an integer type';
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

IF p_keep_table IS NOT NULL THEN
    v_retention_keep_table = p_keep_table;
END IF;
IF p_keep_index IS NOT NULL THEN
    v_retention_keep_index = p_keep_index;
END IF;
IF p_retention_schema IS NOT NULL THEN
    v_retention_schema = p_retention_schema;
END IF;

SELECT schemaname, tablename INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_tables
WHERE schemaname = split_part(p_parent_table, '.', 1)::name
AND tablename = split_part(p_parent_table, '.', 2)::name;

-- Loop through child tables starting from highest to get current max value in partition set
-- Avoids doing a scan on entire partition set and/or getting any values accidentally in default.
FOR v_row_max_id IN
    SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(p_parent_table, 'DESC')
LOOP
        EXECUTE format('SELECT trunc(max(%I)) FROM %I.%I', v_control, v_row_max_id.partition_schemaname, v_row_max_id.partition_tablename) INTO v_max;
        IF v_max IS NOT NULL THEN
            EXIT;
        END IF;
END LOOP;

SELECT sub_parent INTO v_sub_parent FROM @extschema@.part_config_sub WHERE sub_parent = p_parent_table;

-- Loop through child tables of the given parent
-- Must go in ascending order to avoid dropping what may be the "last" partition in the set after dropping tables that match retention period
FOR v_row IN
    SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(p_parent_table, 'ASC')
LOOP
     SELECT child_start_id INTO v_partition_id FROM @extschema@.show_partition_info(v_row.partition_schemaname||'.'||v_row.partition_tablename
        , v_partition_interval::text
        , p_parent_table);

    -- Add one interval to the start of the constraint period
    RAISE DEBUG 'drop_partition_id: v_retention: %, v_max: %, v_partition_id: %, v_partition_interval: %', v_retention, v_max, v_partition_id, v_partition_interval;
    IF v_retention <= (v_max - (v_partition_id + v_partition_interval)) THEN

        -- Do not allow final partition to be dropped if it is not a sub-partition parent
        SELECT count(*) INTO v_count FROM @extschema@.show_partitions(p_parent_table);
        IF v_count = 1 AND v_sub_parent IS NULL THEN
            RAISE WARNING 'Attempt to drop final partition in partition set % as part of retention policy. If you see this message multiple times for the same table, advise reviewing retention policy and/or data entry into the partition set. Also consider setting "infinite_time_partitions = true" if there are large gaps in data insertion.', p_parent_table;
            CONTINUE;
        END IF;

        -- Only create a jobmon entry if there's actual retention work done
        IF v_jobmon_schema IS NOT NULL AND v_job_id IS NULL THEN
            v_job_id := add_job(format('PARTMAN DROP ID PARTITION: %s', p_parent_table));
        END IF;

        IF v_jobmon_schema IS NOT NULL THEN
            v_step_id := add_step(v_job_id, format('Detach/Uninherit table %s.%s from %s', v_row.partition_schemaname, v_row.partition_tablename, p_parent_table));
        END IF;

        IF v_retention_keep_table = true OR v_retention_schema IS NOT NULL THEN
            -- No need to detach partition before dropping since it's going away anyway
            -- TODO Review this to see how to handle based on recent FK issues
            -- Avoids issue of FKs not allowing detachment (Github Issue #294).
            v_sql := format('ALTER TABLE %I.%I DETACH PARTITION %I.%I'
                , v_parent_schema
                , v_parent_tablename
                , v_row.partition_schemaname
                , v_row.partition_tablename);
            EXECUTE v_sql;

            IF v_retention_keep_index = false THEN
                FOR v_index IN
                     WITH child_info AS (
                        SELECT c1.oid
                        FROM pg_catalog.pg_class c1
                        JOIN pg_catalog.pg_namespace n1 ON c1.relnamespace = n1.oid
                        WHERE c1.relname = v_row.partition_tablename::name
                        AND n1.nspname = v_row.partition_schemaname::name
                    )
                    SELECT c.relname as name
                        , con.conname
                    FROM pg_catalog.pg_index i
                    JOIN pg_catalog.pg_class c ON i.indexrelid = c.oid
                    LEFT JOIN pg_catalog.pg_constraint con ON i.indexrelid = con.conindid
                    JOIN child_info ON i.indrelid = child_info.oid
                LOOP
                    IF v_jobmon_schema IS NOT NULL THEN
                        v_step_id := add_step(v_job_id, format('Drop index %s from %s.%s'
                            , v_index.name
                            , v_row.partition_schemaname
                            , v_row.partition_tablename));
                    END IF;
                    IF v_index.conname IS NOT NULL THEN
                        EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I', v_row.partition_schemaname, v_row.partition_tablename, v_index.conname);
                    ELSE
                        EXECUTE format('DROP INDEX %I.%I', v_row.partition_schemaname, v_index.name);
                    END IF;
                    IF v_jobmon_schema IS NOT NULL THEN
                        PERFORM update_step(v_step_id, 'OK', 'Done');
                    END IF;
                END LOOP;
            END IF; -- end v_retention_keep_index IF

            -- Remove table from publication(s) if desired
            IF v_retention_keep_publication = false THEN
                FOR v_pubname_row IN
                    SELECT p.pubname
                    FROM pg_catalog.pg_publication_rel pr
                    JOIN pg_catalog.pg_publication p ON p.oid = pr.prpubid
                    JOIN pg_catalog.pg_class c ON c.oid = pr.prrelid
                    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = v_row.partition_schemaname
                    AND c.relname = v_row.partition_tablename
                LOOP
                    EXECUTE format('ALTER PUBLICATION %I DROP TABLE %I.%I', v_pubname_row.pubname, v_row.partition_schemaname, v_row.partition_tablename);
                END LOOP;
            END IF;

        END IF;

        IF v_retention_schema IS NULL THEN
            IF v_retention_keep_table = false THEN
                IF v_jobmon_schema IS NOT NULL THEN
                    v_step_id := add_step(v_job_id, format('Drop table %s.%s', v_row.partition_schemaname, v_row.partition_tablename));
                END IF;
                v_sql := 'DROP TABLE %I.%I';
                EXECUTE format(v_sql, v_row.partition_schemaname, v_row.partition_tablename);
                IF v_jobmon_schema IS NOT NULL THEN
                    PERFORM update_step(v_step_id, 'OK', 'Done');
                END IF;
            END IF;
        ELSE -- Move to new schema
            IF v_jobmon_schema IS NOT NULL THEN
                v_step_id := add_step(v_job_id, format('Moving table %s.%s to schema %s'
                                                        , v_row.partition_schemaname
                                                        , v_row.partition_tablename
                                                        , v_retention_schema));
            END IF;

            EXECUTE format('ALTER TABLE %I.%I SET SCHEMA %I'
                    , v_row.partition_schemaname
                    , v_row.partition_tablename
                    , v_retention_schema);

            IF v_jobmon_schema IS NOT NULL THEN
                PERFORM update_step(v_step_id, 'OK', 'Done');
            END IF;
        END IF; -- End retention schema if

        -- If child table is a subpartition, remove it from part_config & part_config_sub (should cascade due to FK)
        DELETE FROM @extschema@.part_config WHERE parent_table = v_row.partition_schemaname ||'.'||v_row.partition_tablename;

        v_drop_count := v_drop_count + 1;
    END IF; -- End retention check IF

END LOOP; -- End child table loop

IF v_jobmon_schema IS NOT NULL THEN
    IF v_job_id IS NOT NULL THEN
        v_step_id := add_step(v_job_id, 'Finished partition drop maintenance');
        PERFORM update_step(v_step_id, 'OK', format('%s partitions dropped.', v_drop_count));
        PERFORM close_job(v_job_id);
    END IF;
END IF;

EXECUTE format('SELECT set_config(%L, %L, %L)', 'search_path', v_old_search_path, 'false');

RETURN v_drop_count;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS ex_message = MESSAGE_TEXT,
                                ex_context = PG_EXCEPTION_CONTEXT,
                                ex_detail = PG_EXCEPTION_DETAIL,
                                ex_hint = PG_EXCEPTION_HINT;
        IF v_jobmon_schema IS NOT NULL THEN
            IF v_job_id IS NULL THEN
                EXECUTE format('SELECT %I.add_job(''PARTMAN DROP ID PARTITION: %s'')', v_jobmon_schema, p_parent_table) INTO v_job_id;
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


CREATE OR REPLACE FUNCTION @extschema@.drop_partition_time(
    p_parent_table text
    , p_retention interval DEFAULT NULL
    , p_keep_table boolean DEFAULT NULL
    , p_keep_index boolean DEFAULT NULL
    , p_retention_schema text DEFAULT NULL
    , p_reference_timestamp timestamptz DEFAULT CURRENT_TIMESTAMP
)
    RETURNS int
    LANGUAGE plpgsql
    AS $$
DECLARE

ex_context                          text;
ex_detail                           text;
ex_hint                             text;
ex_message                          text;
v_adv_lock                          boolean;
v_control                           text;
v_control_type                      text;
v_count                             int;
v_drop_count                        int := 0;
v_epoch                             text;
v_index                             record;
v_job_id                            bigint;
v_jobmon                            boolean;
v_jobmon_schema                     text;
v_new_search_path                   text;
v_old_search_path                   text;
v_parent_schema                     text;
v_parent_tablename                  text;
v_partition_interval                interval;
v_partition_timestamp               timestamptz;
v_pubname_row                       record;
v_retention                         interval;
v_retention_keep_index              boolean;
v_retention_keep_table              boolean;
v_retention_keep_publication        boolean;
v_retention_schema                  text;
v_row                               record;
v_sql                               text;
v_step_id                           bigint;
v_sub_parent                        text;

BEGIN
/*
 * Function to drop child tables from a time-based partition set.
 * Options to move table to different schema, drop only indexes or actually drop the table from the database.
 */

v_adv_lock := pg_try_advisory_xact_lock(hashtext('pg_partman drop_partition_time'));
IF v_adv_lock = 'false' THEN
    RAISE NOTICE 'drop_partition_time already running.';
    RETURN 0;
END IF;

-- Allow override of configuration options
IF p_retention IS NULL THEN
    SELECT
        control
        , partition_interval::interval
        , epoch
        , retention::interval
        , retention_keep_table
        , retention_keep_index
        , retention_keep_publication
        , retention_schema
        , jobmon
    INTO
        v_control
        , v_partition_interval
        , v_epoch
        , v_retention
        , v_retention_keep_table
        , v_retention_keep_index
        , v_retention_keep_publication
        , v_retention_schema
        , v_jobmon
    FROM @extschema@.part_config
    WHERE parent_table = p_parent_table
    AND retention IS NOT NULL;

    IF v_partition_interval IS NULL THEN
        RAISE EXCEPTION 'Configuration for given parent table with a retention period not found: %', p_parent_table;
    END IF;
ELSE
    SELECT
        partition_interval::interval
        , epoch
        , retention_keep_table
        , retention_keep_index
        , retention_keep_publication
        , retention_schema
        , jobmon
    INTO
        v_partition_interval
        , v_epoch
        , v_retention_keep_table
        , v_retention_keep_index
        , v_retention_keep_publication
        , v_retention_schema
        , v_jobmon
    FROM @extschema@.part_config
    WHERE parent_table = p_parent_table;
    v_retention := p_retention;

    IF v_partition_interval IS NULL THEN
        RAISE EXCEPTION 'Configuration for given parent table not found: %', p_parent_table;
    END IF;
END IF;

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

IF p_keep_table IS NOT NULL THEN
    v_retention_keep_table = p_keep_table;
END IF;
IF p_keep_index IS NOT NULL THEN
    v_retention_keep_index = p_keep_index;
END IF;
IF p_retention_schema IS NOT NULL THEN
    v_retention_schema = p_retention_schema;
END IF;

SELECT schemaname, tablename INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_tables
WHERE schemaname = split_part(p_parent_table, '.', 1)::name
AND tablename = split_part(p_parent_table, '.', 2)::name;

SELECT sub_parent INTO v_sub_parent FROM @extschema@.part_config_sub WHERE sub_parent = p_parent_table;

-- Loop through child tables of the given parent
-- Must go in ascending order to avoid dropping what may be the "last" partition in the set after dropping tables that match retention period
FOR v_row IN
    SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(p_parent_table, 'ASC')
LOOP
    -- pull out datetime portion of partition's tablename to make the next one
     SELECT child_start_time INTO v_partition_timestamp FROM @extschema@.show_partition_info(v_row.partition_schemaname||'.'||v_row.partition_tablename
        , v_partition_interval::text
        , p_parent_table);
    -- Add one interval since partition names contain the start of the constraint period
    IF (v_partition_timestamp + v_partition_interval) < (p_reference_timestamp - v_retention) THEN

        -- Do not allow final partition to be dropped if it is not a sub-partition parent
        SELECT count(*) INTO v_count FROM @extschema@.show_partitions(p_parent_table);
        IF v_count = 1 AND v_sub_parent IS NULL THEN
            RAISE WARNING 'Attempt to drop final partition in partition set % as part of retention policy. If you see this message multiple times for the same table, advise reviewing retention policy and/or data entry into the partition set. Also consider setting "infinite_time_partitions = true" if there are large gaps in data insertion.).', p_parent_table;
            CONTINUE;
        END IF;

        -- Only create a jobmon entry if there's actual retention work done
        IF v_jobmon_schema IS NOT NULL AND v_job_id IS NULL THEN
            v_job_id := add_job(format('PARTMAN DROP TIME PARTITION: %s', p_parent_table));
        END IF;

        IF v_jobmon_schema IS NOT NULL THEN
            v_step_id := add_step(v_job_id, format('Detach/Uninherit table %s.%s from %s'
                                                , v_row.partition_schemaname
                                                , v_row.partition_tablename
                                                , p_parent_table));
        END IF;
        IF v_retention_keep_table = true OR v_retention_schema IS NOT NULL THEN
            -- No need to detach partition before dropping since it's going away anyway
            -- TODO Review this to see how to handle based on recent FK issues
            -- Avoids issue of FKs not allowing detachment (Github Issue #294).
            v_sql := format('ALTER TABLE %I.%I DETACH PARTITION %I.%I'
                , v_parent_schema
                , v_parent_tablename
                , v_row.partition_schemaname
                , v_row.partition_tablename);
            EXECUTE v_sql;

            IF v_retention_keep_index = false THEN
                    FOR v_index IN
                        WITH child_info AS (
                            SELECT c1.oid
                            FROM pg_catalog.pg_class c1
                            JOIN pg_catalog.pg_namespace n1 ON c1.relnamespace = n1.oid
                            WHERE c1.relname = v_row.partition_tablename::name
                            AND n1.nspname = v_row.partition_schemaname::name
                        )
                        SELECT c.relname as name
                            , con.conname
                        FROM pg_catalog.pg_index i
                        JOIN pg_catalog.pg_class c ON i.indexrelid = c.oid
                        LEFT JOIN pg_catalog.pg_constraint con ON i.indexrelid = con.conindid
                        JOIN child_info ON i.indrelid = child_info.oid
                    LOOP
                        IF v_jobmon_schema IS NOT NULL THEN
                            v_step_id := add_step(v_job_id, format('Drop index %s from %s.%s'
                                                                , v_index.name
                                                                , v_row.partition_schemaname
                                                                , v_row.partition_tablename));
                        END IF;
                        IF v_index.conname IS NOT NULL THEN
                            EXECUTE format('ALTER TABLE %I.%I DROP CONSTRAINT %I'
                                            , v_row.partition_schemaname
                                            , v_row.partition_tablename
                                            , v_index.conname);
                        ELSE
                            EXECUTE format('DROP INDEX %I.%I', v_parent_schema, v_index.name);
                        END IF;
                        IF v_jobmon_schema IS NOT NULL THEN
                            PERFORM update_step(v_step_id, 'OK', 'Done');
                        END IF;
                    END LOOP;
            END IF; -- end v_retention_keep_index IF


            -- Remove table from publication(s) if desired
            IF v_retention_keep_publication = false THEN

                FOR v_pubname_row IN
                    SELECT p.pubname
                    FROM pg_catalog.pg_publication_rel pr
                    JOIN pg_catalog.pg_publication p ON p.oid = pr.prpubid
                    JOIN pg_catalog.pg_class c ON c.oid = pr.prrelid
                    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = v_row.partition_schemaname
                    AND c.relname = v_row.partition_tablename
                LOOP
                    EXECUTE format('ALTER PUBLICATION %I DROP TABLE %I.%I', v_pubname_row.pubname, v_row.partition_schemaname, v_row.partition_tablename);
                END LOOP;

            END IF;

        END IF;

        IF v_jobmon_schema IS NOT NULL THEN
            PERFORM update_step(v_step_id, 'OK', 'Done');
        END IF;

        IF v_retention_schema IS NULL THEN
            IF v_retention_keep_table = false THEN
                IF v_jobmon_schema IS NOT NULL THEN
                    v_step_id := add_step(v_job_id, format('Drop table %s.%s', v_row.partition_schemaname, v_row.partition_tablename));
                END IF;
                v_sql := 'DROP TABLE %I.%I';
                EXECUTE format(v_sql, v_row.partition_schemaname, v_row.partition_tablename);
                IF v_jobmon_schema IS NOT NULL THEN
                    PERFORM update_step(v_step_id, 'OK', 'Done');
                END IF;
            END IF;
        ELSE -- Move to new schema
            IF v_jobmon_schema IS NOT NULL THEN
                v_step_id := add_step(v_job_id, format('Moving table %s.%s to schema %s'
                                                , v_row.partition_schemaname
                                                , v_row.partition_tablename
                                                , v_retention_schema));
            END IF;

            EXECUTE format('ALTER TABLE %I.%I SET SCHEMA %I', v_row.partition_schemaname, v_row.partition_tablename, v_retention_schema);


            IF v_jobmon_schema IS NOT NULL THEN
                PERFORM update_step(v_step_id, 'OK', 'Done');
            END IF;
        END IF; -- End retention schema if

        -- If child table is a subpartition, remove it from part_config & part_config_sub (should cascade due to FK)
        DELETE FROM @extschema@.part_config WHERE parent_table = v_row.partition_schemaname||'.'||v_row.partition_tablename;

        v_drop_count := v_drop_count + 1;
    END IF; -- End retention check IF

END LOOP; -- End child table loop

IF v_jobmon_schema IS NOT NULL THEN
    IF v_job_id IS NOT NULL THEN
        v_step_id := add_step(v_job_id, 'Finished partition drop maintenance');
        PERFORM update_step(v_step_id, 'OK', format('%s partitions dropped.', v_drop_count));
        PERFORM close_job(v_job_id);
    END IF;
END IF;

EXECUTE format('SELECT set_config(%L, %L, %L)', 'search_path', v_old_search_path, 'false');

RETURN v_drop_count;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS ex_message = MESSAGE_TEXT,
                                ex_context = PG_EXCEPTION_CONTEXT,
                                ex_detail = PG_EXCEPTION_DETAIL,
                                ex_hint = PG_EXCEPTION_HINT;
        IF v_jobmon_schema IS NOT NULL THEN
            IF v_job_id IS NULL THEN
                EXECUTE format('SELECT %I.add_job(''PARTMAN DROP TIME PARTITION: %s'')', v_jobmon_schema, p_parent_table) INTO v_job_id;
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


-- Drop and restore gapfill function to remove analyze parameter added in version 4.8
CREATE FUNCTION @extschema@.partition_gap_fill(p_parent_table text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE

v_child_created                     boolean;
v_children_created_count            int := 0;
v_control                           text;
v_control_type                      text;
v_current_child_start_id            bigint;
v_current_child_start_timestamp     timestamptz;
v_epoch                             text;
v_expected_next_child_id            bigint;
v_expected_next_child_timestamp     timestamptz;
v_final_child_schemaname            text;
v_final_child_start_id              bigint;
v_final_child_start_timestamp       timestamptz;
v_final_child_tablename             text;
v_interval_id                       bigint;
v_interval_time                     interval;
v_previous_child_schemaname         text;
v_previous_child_tablename          text;
v_previous_child_start_id           bigint;
v_previous_child_start_timestamp    timestamptz;
v_parent_schema                     text;
v_parent_table                      text;
v_parent_tablename                  text;
v_partition_interval                text;
v_row                               record;

BEGIN

SELECT parent_table, partition_interval, control, epoch
INTO v_parent_table, v_partition_interval, v_control, v_epoch
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;
IF v_parent_table IS NULL THEN
    RAISE EXCEPTION 'Given parent table has no configuration in pg_partman: %', p_parent_table;
END IF;

SELECT n.nspname, c.relname INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_parent_table, '.', 1)::name
AND c.relname = split_part(p_parent_table, '.', 2)::name;
    IF v_parent_tablename IS NULL THEN
        RAISE EXCEPTION 'Unable to find given parent table in system catalogs. Ensure it is schema qualified: %', p_parent_table;
    END IF;

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_parent_schema, v_parent_tablename, v_control);

SELECT partition_schemaname, partition_tablename
INTO v_final_child_schemaname, v_final_child_tablename
FROM @extschema@.show_partitions(v_parent_table, 'DESC')
LIMIT 1;

IF v_control_type = 'time'  OR (v_control_type = 'id' AND v_epoch <> 'none') THEN

    v_interval_time := v_partition_interval::interval;

    SELECT child_start_time INTO v_final_child_start_timestamp
        FROM @extschema@.show_partition_info(format('%s', v_final_child_schemaname||'.'||v_final_child_tablename), p_parent_table := v_parent_table);

    FOR v_row IN
        SELECT partition_schemaname, partition_tablename
        FROM @extschema@.show_partitions(v_parent_table, 'ASC')
    LOOP

        RAISE DEBUG 'v_row.partition_tablename: %, v_final_child_start_timestamp: %', v_row.partition_tablename, v_final_child_start_timestamp;

        IF v_previous_child_tablename IS NULL THEN
            v_previous_child_schemaname := v_row.partition_schemaname;
            v_previous_child_tablename := v_row.partition_tablename;
            SELECT child_start_time INTO v_previous_child_start_timestamp
                FROM @extschema@.show_partition_info(format('%s', v_previous_child_schemaname||'.'||v_previous_child_tablename), p_parent_table := v_parent_table);
            CONTINUE;
        END IF;

        v_expected_next_child_timestamp := v_previous_child_start_timestamp + v_interval_time;

        RAISE DEBUG 'v_expected_next_child_timestamp: %', v_expected_next_child_timestamp;

        IF v_expected_next_child_timestamp = v_final_child_start_timestamp THEN
            EXIT;
        END IF;

        SELECT child_start_time INTO v_current_child_start_timestamp
            FROM @extschema@.show_partition_info(format('%s', v_row.partition_schemaname||'.'||v_row.partition_tablename), p_parent_table := v_parent_table);

        RAISE DEBUG 'v_current_child_start_timestamp: %', v_current_child_start_timestamp;

        IF v_expected_next_child_timestamp != v_current_child_start_timestamp THEN
            v_child_created :=  @extschema@.create_partition_time(v_parent_table, ARRAY[v_expected_next_child_timestamp]);
            IF v_child_created THEN
                v_children_created_count := v_children_created_count + 1;
                v_child_created := false;
            END IF;
            SELECT partition_schema, partition_table INTO v_previous_child_schemaname, v_previous_child_tablename
                FROM @extschema@.show_partition_name(v_parent_table, v_expected_next_child_timestamp::text);
            -- Need to stay in another inner loop until the next expected child timestamp matches the current one
            -- Once it does, exit. This means gap is filled.
            LOOP
                v_previous_child_start_timestamp := v_expected_next_child_timestamp;
                v_expected_next_child_timestamp := v_expected_next_child_timestamp + v_interval_time;
                IF v_expected_next_child_timestamp = v_current_child_start_timestamp THEN
                    EXIT;
                ELSE

        RAISE DEBUG 'inner loop: v_previous_child_start_timestamp: %, v_expected_next_child_timestamp: %, v_children_created_count: %'
                , v_previous_child_start_timestamp, v_expected_next_child_timestamp, v_children_created_count;

                    v_child_created := @extschema@.create_partition_time(v_parent_table, ARRAY[v_expected_next_child_timestamp]);
                    IF v_child_created THEN
                        v_children_created_count := v_children_created_count + 1;
                        v_child_created := false;
                    END IF;
                END IF;
            END LOOP; -- end expected child loop
        END IF;

        v_previous_child_schemaname := v_row.partition_schemaname;
        v_previous_child_tablename := v_row.partition_tablename;
        SELECT child_start_time INTO v_previous_child_start_timestamp
            FROM @extschema@.show_partition_info(format('%s', v_previous_child_schemaname||'.'||v_previous_child_tablename), p_parent_table := v_parent_table);

    END LOOP; -- end time loop

ELSIF v_control_type = 'id' THEN

    v_interval_id := v_partition_interval::bigint;

    SELECT child_start_id INTO v_final_child_start_id
        FROM @extschema@.show_partition_info(format('%s', v_final_child_schemaname||'.'||v_final_child_tablename), p_parent_table := v_parent_table);

    FOR v_row IN
        SELECT partition_schemaname, partition_tablename
        FROM @extschema@.show_partitions(v_parent_table, 'ASC')
    LOOP

        RAISE DEBUG 'v_row.partition_tablename: %, v_final_child_start_id: %', v_row.partition_tablename, v_final_child_start_id;

        IF v_previous_child_tablename IS NULL THEN
            v_previous_child_schemaname := v_row.partition_schemaname;
            v_previous_child_tablename := v_row.partition_tablename;
            SELECT child_start_id INTO v_previous_child_start_id
                FROM @extschema@.show_partition_info(format('%s', v_previous_child_schemaname||'.'||v_previous_child_tablename), p_parent_table := v_parent_table);
            CONTINUE;
        END IF;

        v_expected_next_child_id := v_previous_child_start_id + v_interval_id;

        RAISE DEBUG 'v_expected_next_child_id: %', v_expected_next_child_id;

        IF v_expected_next_child_id = v_final_child_start_id THEN
            EXIT;
        END IF;

        SELECT child_start_id INTO v_current_child_start_id
            FROM @extschema@.show_partition_info(format('%s', v_row.partition_schemaname||'.'||v_row.partition_tablename), p_parent_table := v_parent_table);

        RAISE DEBUG 'v_current_child_start_id: %', v_current_child_start_id;

        IF v_expected_next_child_id != v_current_child_start_id THEN
            v_child_created :=  @extschema@.create_partition_id(v_parent_table, ARRAY[v_expected_next_child_id]);
            IF v_child_created THEN
                v_children_created_count := v_children_created_count + 1;
                v_child_created := false;
            END IF;
            SELECT partition_schema, partition_table INTO v_previous_child_schemaname, v_previous_child_tablename
                FROM @extschema@.show_partition_name(v_parent_table, v_expected_next_child_id::text);
            -- Need to stay in another inner loop until the next expected child id matches the current one
            -- Once it does, exit. This means gap is filled.
            LOOP
                v_previous_child_start_id := v_expected_next_child_id;
                v_expected_next_child_id := v_expected_next_child_id + v_interval_id;
                IF v_expected_next_child_id = v_current_child_start_id THEN
                    EXIT;
                ELSE

        RAISE DEBUG 'inner loop: v_previous_child_start_id: %, v_expected_next_child_id: %, v_children_created_count: %'
                , v_previous_child_start_id, v_expected_next_child_id, v_children_created_count;

                    v_child_created := @extschema@.create_partition_id(v_parent_table, ARRAY[v_expected_next_child_id]);
                    IF v_child_created THEN
                        v_children_created_count := v_children_created_count + 1;
                        v_child_created := false;
                    END IF;
                END IF;
            END LOOP; -- end expected child loop
        END IF;

        v_previous_child_schemaname := v_row.partition_schemaname;
        v_previous_child_tablename := v_row.partition_tablename;
        SELECT child_start_id INTO v_previous_child_start_id
            FROM @extschema@.show_partition_info(format('%s', v_previous_child_schemaname||'.'||v_previous_child_tablename), p_parent_table := v_parent_table);

    END LOOP; -- end id loop

END IF; -- end time/id if

RETURN v_children_created_count;

END
$$;


CREATE OR REPLACE FUNCTION @extschema@.check_subpartition_limits(p_parent_table text, p_type text, OUT sub_min text, OUT sub_max text) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE

v_parent_schema         text;
v_parent_tablename      text;
v_top_control           text;
v_top_control_type      text;
v_top_epoch             text;
v_top_interval          text;
v_top_schema            text;
v_top_tablename         text;

BEGIN
/*
 * Check if parent table is a subpartition of an already existing partition set managed by pg_partman
 *  If so, return the limits of what child tables can be created under the given parent table based on its own suffix
 *  If not, return NULL. Allows caller to check for NULL and then know if the given parent has sub-partition limits.
 */

SELECT n.nspname, c.relname INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_parent_table, '.', 1)::name
AND c.relname = split_part(p_parent_table, '.', 2)::name;

WITH top_oid AS (
    SELECT i.inhparent AS top_parent_oid
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_inherits i ON c.oid = i.inhrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = v_parent_schema
    AND c.relname = v_parent_tablename
)
SELECT n.nspname, c.relname, p.partition_interval, p.control, p.epoch
INTO v_top_schema, v_top_tablename, v_top_interval, v_top_control, v_top_epoch
FROM pg_catalog.pg_class c
JOIN top_oid t ON c.oid = t.top_parent_oid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
JOIN @extschema@.part_config p ON p.parent_table = n.nspname||'.'||c.relname
WHERE c.oid = t.top_parent_oid;

SELECT general_type INTO v_top_control_type
FROM @extschema@.check_control_type(v_top_schema, v_top_tablename, v_top_control);

IF v_top_control_type = 'id' AND v_top_epoch <> 'none' THEN
    v_top_control_type := 'time';
END IF;

-- If sub-partition is different type than top parent, no need to set limits
IF p_type = v_top_control_type THEN
    IF p_type = 'time' THEN
        SELECT child_start_time::text, child_end_time::text
        INTO sub_min, sub_max
        FROM @extschema@.show_partition_info(p_parent_table, v_top_interval, v_top_schema||'.'||v_top_tablename);
    ELSIF p_type = 'id' THEN
        -- Trunc to handle numeric values
        SELECT trunc(child_start_id)::text, trunc(child_end_id)::text
        INTO sub_min, sub_max
        FROM @extschema@.show_partition_info(p_parent_table, v_top_interval, v_top_schema||'.'||v_top_tablename);
    ELSE
        RAISE EXCEPTION 'Reached unknown state in check_subpartition_limits(). Please report what lead to this condition to author';
    END IF;
END IF;

RETURN;

END
$$;


CREATE OR REPLACE FUNCTION @extschema@.partition_data_id(
    p_parent_table text
    , p_batch_count int DEFAULT 1
    , p_batch_interval bigint DEFAULT NULL
    , p_lock_wait numeric DEFAULT 0
    , p_order text DEFAULT 'ASC'
    , p_analyze boolean DEFAULT true
    , p_source_table text DEFAULT NULL
    , p_ignored_columns text[] DEFAULT NULL
)
    RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE

v_analyze                   boolean := FALSE;
v_column_list               text;
v_control                   text;
v_control_type              text;
v_current_partition_name    text;
v_default_exists            boolean;
v_default_schemaname        text;
v_default_tablename         text;
v_epoch                     text;
v_lock_iter                 int := 1;
v_lock_obtained             boolean := FALSE;
v_max_partition_id          bigint;
v_min_partition_id          bigint;
v_parent_schema             text;
v_parent_tablename          text;
v_partition_interval        bigint;
v_partition_id              bigint[];
v_rowcount                  bigint;
v_source_schemaname         text;
v_source_tablename          text;
v_sql                       text;
v_start_control             bigint;
v_total_rows                bigint := 0;

BEGIN
    /*
     * Populate the child table(s) of an id-based partition set with data from the default or other given source
     */

    SELECT partition_interval::bigint
    , control
    , epoch
    INTO v_partition_interval
    , v_control
    , v_epoch
    FROM @extschema@.part_config
    WHERE parent_table = p_parent_table;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'ERROR: No entry in part_config found for given table:  %', p_parent_table;
    END IF;

SELECT schemaname, tablename INTO v_source_schemaname, v_source_tablename
FROM pg_catalog.pg_tables
WHERE schemaname = split_part(p_parent_table, '.', 1)::name
AND tablename = split_part(p_parent_table, '.', 2)::name;

-- Preserve given parent tablename for use below
v_parent_schema    := v_source_schemaname;
v_parent_tablename := v_source_tablename;

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_source_schemaname, v_source_tablename, v_control);

IF v_control_type <> 'id' OR (v_control_type = 'id' AND v_epoch <> 'none') THEN
    RAISE EXCEPTION 'Control column for given partition set is not id/serial based or epoch flag is set for time-based partitioning.';
END IF;

IF p_source_table IS NOT NULL THEN
    -- Set source table to user given source table instead of parent table
    v_source_schemaname := NULL;
    v_source_tablename := NULL;

    SELECT schemaname, tablename INTO v_source_schemaname, v_source_tablename
    FROM pg_catalog.pg_tables
    WHERE schemaname = split_part(p_source_table, '.', 1)::name
    AND tablename = split_part(p_source_table, '.', 2)::name;

    IF v_source_tablename IS NULL THEN
        RAISE EXCEPTION 'Given source table does not exist in system catalogs: %', p_source_table;
    END IF;

ELSE

    IF p_batch_interval IS NOT NULL AND p_batch_interval != v_partition_interval THEN
        -- This is true because all data for a given child table must be moved out of the default partition before the child table can be created.
        -- So cannot create the child table when only some of the data has been moved out of the default partition.
        RAISE EXCEPTION 'Custom intervals are not allowed when moving data out of the DEFAULT partition. Please leave p_interval/p_batch_interval parameters unset or NULL to allow use of partition set''s default partitioning interval.';
    END IF;

    -- Set source table to default table if p_source_table is not set, and it exists
    -- Otherwise just return with a DEBUG that no data source exists
    SELECT n.nspname::text, c.relname::text
    INTO v_default_schemaname, v_default_tablename
    FROM pg_catalog.pg_inherits h
    JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE h.inhparent = format('%I.%I', v_source_schemaname, v_source_tablename)::regclass
    AND pg_get_expr(relpartbound, c.oid) = 'DEFAULT';

    IF v_default_tablename IS NOT NULL THEN
        v_source_schemaname := v_default_schemaname;
        v_source_tablename := v_default_tablename;

        v_default_exists := true;
        EXECUTE format ('CREATE TEMP TABLE IF NOT EXISTS partman_temp_data_storage (LIKE %I.%I INCLUDING INDEXES) ON COMMIT DROP', v_source_schemaname, v_source_tablename);
    ELSE
        RAISE DEBUG 'No default table found when partition_data_id() was called';
        RETURN v_total_rows;
    END IF;

END IF;

IF p_batch_interval IS NULL OR p_batch_interval > v_partition_interval THEN
    p_batch_interval := v_partition_interval;
END IF;

-- Generate column list to use in SELECT/INSERT statements below. Allows for exclusion of GENERATED (or any other desired) columns.
SELECT string_agg(quote_ident(attname), ',')
INTO v_column_list
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = v_source_schemaname
AND c.relname = v_source_tablename
AND a.attnum > 0
AND a.attisdropped = false
AND attname <> ALL(COALESCE(p_ignored_columns, ARRAY[]::text[]));

FOR i IN 1..p_batch_count LOOP

    IF p_order = 'ASC' THEN
        EXECUTE format('SELECT min(%I) FROM ONLY %I.%I', v_control, v_source_schemaname, v_source_tablename) INTO v_start_control;
        IF v_start_control IS NULL THEN
            EXIT;
        END IF;
        v_min_partition_id = v_start_control - (v_start_control % v_partition_interval);
        v_partition_id := ARRAY[v_min_partition_id];
        -- Check if custom batch interval overflows current partition maximum
        IF (v_start_control + p_batch_interval) >= (v_min_partition_id + v_partition_interval) THEN
            v_max_partition_id := v_min_partition_id + v_partition_interval;
        ELSE
            v_max_partition_id := v_start_control + p_batch_interval;
        END IF;

    ELSIF p_order = 'DESC' THEN
        EXECUTE format('SELECT max(%I) FROM ONLY %I.%I', v_control, v_source_schemaname, v_source_tablename) INTO v_start_control;
        IF v_start_control IS NULL THEN
            EXIT;
        END IF;
        v_min_partition_id = v_start_control - (v_start_control % v_partition_interval);
        -- Must be greater than max value still in parent table since query below grabs < max
        v_max_partition_id := v_min_partition_id + v_partition_interval;
        v_partition_id := ARRAY[v_min_partition_id];
        -- Make sure minimum doesn't underflow current partition minimum
        IF (v_start_control - p_batch_interval) >= v_min_partition_id THEN
            v_min_partition_id = v_start_control - p_batch_interval;
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
                v_sql := format('SELECT %s FROM ONLY %I.%I WHERE %I >= %s AND %I < %s FOR UPDATE NOWAIT'
                    , v_column_list
                    , v_source_schemaname
                    , v_source_tablename
                    , v_control
                    , v_min_partition_id
                    , v_control
                    , v_max_partition_id);
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

v_current_partition_name := @extschema@.check_name_length(COALESCE(v_parent_tablename), v_min_partition_id::text, TRUE);

IF v_default_exists THEN

    -- Child tables cannot be created if data that belongs to it exists in the default
    -- Have to move data out to temporary location, create child table, then move it back

    -- Temp table created above to avoid excessive temp creation in loop
    EXECUTE format('WITH partition_data AS (
            DELETE FROM %1$I.%2$I WHERE %3$I >= %4$s AND %3$I < %5$s RETURNING *)
        INSERT INTO partman_temp_data_storage (%6$s) SELECT %6$s FROM partition_data'
        , v_source_schemaname
        , v_source_tablename
        , v_control
        , v_min_partition_id
        , v_max_partition_id
        , v_column_list);

    -- Set analyze to true if a table is created
    v_analyze := @extschema@.create_partition_id(p_parent_table, v_partition_id);

    EXECUTE format('WITH partition_data AS (
            DELETE FROM partman_temp_data_storage RETURNING *)
        INSERT INTO %1$I.%2$I (%3$s) SELECT %3$s FROM partition_data'
        , v_parent_schema
        , v_current_partition_name
        , v_column_list);

ELSE

    -- Set analyze to true if a table is created
    v_analyze := @extschema@.create_partition_id(p_parent_table, v_partition_id);

    EXECUTE format('WITH partition_data AS (
            DELETE FROM ONLY %1$I.%2$I WHERE %3$I >= %4$s AND %3$I < %5$s RETURNING *)
        INSERT INTO %6$I.%7$I (%8$s) SELECT %8$s FROM partition_data'
        , v_source_schemaname
        , v_source_tablename
        , v_control
        , v_min_partition_id
        , v_max_partition_id
        , v_parent_schema
        , v_current_partition_name
        , v_column_list);

END IF;

GET DIAGNOSTICS v_rowcount = ROW_COUNT;
v_total_rows := v_total_rows + v_rowcount;
IF v_rowcount = 0 THEN
    EXIT;
END IF;

END LOOP;

-- v_analyze is a local check if a new table is made.
-- p_analyze is a parameter to say whether to run the analyze at all. Used by create_parent() to avoid long exclusive lock or run_maintenence() to avoid long creation runs.
IF v_analyze AND p_analyze THEN
    RAISE DEBUG 'partiton_data_time: Begin analyze of %.%', v_parent_schema, v_parent_tablename;
    EXECUTE format('ANALYZE %I.%I', v_parent_schema, v_parent_tablename);
    RAISE DEBUG 'partiton_data_time: End analyze of %.%', v_parent_schema, v_parent_tablename;
END IF;

RETURN v_total_rows;

END
$$;


CREATE OR REPLACE FUNCTION @extschema@.partition_data_time(
    p_parent_table text
    , p_batch_count int DEFAULT 1
    , p_batch_interval interval DEFAULT NULL
    , p_lock_wait numeric DEFAULT 0
    , p_order text DEFAULT 'ASC'
    , p_analyze boolean DEFAULT true
    , p_source_table text DEFAULT NULL
    , p_ignored_columns text[] DEFAULT NULL
)
    RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE

v_analyze                   boolean := FALSE;
v_column_list               text;
v_control                   text;
v_control_type              text;
v_datetime_string           text;
v_current_partition_name    text;
v_default_exists            boolean;
v_default_schemaname        text;
v_default_tablename         text;
v_epoch                     text;
v_last_partition            text;
v_lock_iter                 int := 1;
v_lock_obtained             boolean := FALSE;
v_max_partition_timestamp   timestamptz;
v_min_partition_timestamp   timestamptz;
v_parent_schema             text;
v_parent_tablename          text;
v_partition_expression      text;
v_partition_interval        interval;
v_partition_suffix          text;
v_partition_timestamp       timestamptz[];
v_source_schemaname         text;
v_source_tablename          text;
v_rowcount                  bigint;
v_start_control             timestamptz;
v_total_rows                bigint := 0;

BEGIN
/*
 * Populate the child table(s) of a time-based partition set with old data from the original parent
 */

SELECT partition_interval::interval
    , control
    , datetime_string
    , epoch
INTO v_partition_interval
    , v_control
    , v_datetime_string
    , v_epoch
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;
IF NOT FOUND THEN
    RAISE EXCEPTION 'ERROR: No entry in part_config found for given table:  %', p_parent_table;
END IF;

SELECT schemaname, tablename INTO v_source_schemaname, v_source_tablename
FROM pg_catalog.pg_tables
WHERE schemaname = split_part(p_parent_table, '.', 1)::name
AND tablename = split_part(p_parent_table, '.', 2)::name;

-- Preserve real parent tablename for use below
v_parent_schema    := v_source_schemaname;
v_parent_tablename := v_source_tablename;

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_source_schemaname, v_source_tablename, v_control);

IF v_control_type <> 'time' THEN
    IF (v_control_type = 'id' AND v_epoch = 'none') OR v_control_type <> 'id' THEN
        RAISE EXCEPTION 'Cannot run on partition set without time based control column or epoch flag set with an id column. Found control: %, epoch: %', v_control_type, v_epoch;
    END IF;
END IF;

-- Replace the parent variables with the source variables if using source table for child table data
IF p_source_table IS NOT NULL THEN
    -- Set source table to user given source table instead of parent table
    v_source_schemaname := NULL;
    v_source_tablename := NULL;

    SELECT schemaname, tablename INTO v_source_schemaname, v_source_tablename
    FROM pg_catalog.pg_tables
    WHERE schemaname = split_part(p_source_table, '.', 1)::name
    AND tablename = split_part(p_source_table, '.', 2)::name;

    IF v_source_tablename IS NULL THEN
        RAISE EXCEPTION 'Given source table does not exist in system catalogs: %', p_source_table;
    END IF;


ELSE

    IF p_batch_interval IS NOT NULL AND p_batch_interval != v_partition_interval THEN
        -- This is true because all data for a given child table must be moved out of the default partition before the child table can be created.
        -- So cannot create the child table when only some of the data has been moved out of the default partition.
        RAISE EXCEPTION 'Custom intervals are not allowed when moving data out of the DEFAULT partition. Please leave p_interval/p_batch_interval parameters unset or NULL to allow use of partition set''s default partitioning interval.';
    END IF;

    -- Set source table to default table if p_source_table is not set, and it exists
    -- Otherwise just return with a DEBUG that no data source exists
    SELECT n.nspname::text, c.relname::text
    INTO v_default_schemaname, v_default_tablename
    FROM pg_catalog.pg_inherits h
    JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE h.inhparent = format('%I.%I', v_source_schemaname, v_source_tablename)::regclass
    AND pg_get_expr(relpartbound, c.oid) = 'DEFAULT';

    IF v_default_tablename IS NOT NULL THEN
        v_source_schemaname := v_default_schemaname;
        v_source_tablename := v_default_tablename;

        v_default_exists := true;
        EXECUTE format ('CREATE TEMP TABLE IF NOT EXISTS partman_temp_data_storage (LIKE %I.%I INCLUDING INDEXES) ON COMMIT DROP', v_source_schemaname, v_source_tablename);
    ELSE
        RAISE DEBUG 'No default table found when partition_data_time() was called';
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
    WHEN v_epoch = 'nanoseconds' THEN format('to_timestamp((%I/1000000000)::float)', v_control)
    ELSE format('%I', v_control)
END;

-- Generate column list to use in SELECT/INSERT statements below. Allows for exclusion of GENERATED (or any other desired) columns.
SELECT string_agg(quote_ident(attname), ',')
INTO v_column_list
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = v_source_schemaname
AND c.relname = v_source_tablename
AND a.attnum > 0
AND a.attisdropped = false
AND attname <> ALL(COALESCE(p_ignored_columns, ARRAY[]::text[]));

FOR i IN 1..p_batch_count LOOP

    IF p_order = 'ASC' THEN
        EXECUTE format('SELECT min(%s) FROM ONLY %I.%I', v_partition_expression, v_source_schemaname, v_source_tablename) INTO v_start_control;
    ELSIF p_order = 'DESC' THEN
        EXECUTE format('SELECT max(%s) FROM ONLY %I.%I', v_partition_expression, v_source_schemaname, v_source_tablename) INTO v_start_control;
    ELSE
        RAISE EXCEPTION 'Invalid value for p_order. Must be ASC or DESC';
    END IF;

    IF v_start_control IS NULL THEN
        EXIT;
    END IF;

    SELECT child_start_time INTO v_min_partition_timestamp FROM @extschema@.show_partition_info(v_source_schemaname||'.'||v_last_partition
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
            v_min_partition_timestamp = v_start_control - p_batch_interval;
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
                EXECUTE format('SELECT %s FROM ONLY %I.%I WHERE %s >= %L AND %4$s < %6$L FOR UPDATE NOWAIT'
                    , v_column_list
                    , v_source_schemaname
                    , v_source_tablename
                    , v_partition_expression
                    , v_min_partition_timestamp
                    , v_max_partition_timestamp);
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

    IF v_default_exists THEN
        -- Child tables cannot be created if data that belongs to it exists in the default
        -- Have to move data out to temporary location, create child table, then move it back

        -- Temp table created above to avoid excessive temp creation in loop
        EXECUTE format('WITH partition_data AS (
                DELETE FROM %1$I.%2$I WHERE %3$s >= %4$L AND %3$s < %5$L RETURNING *)
            INSERT INTO partman_temp_data_storage (%6$s) SELECT %6$s FROM partition_data'
            , v_source_schemaname
            , v_source_tablename
            , v_partition_expression
            , v_min_partition_timestamp
            , v_max_partition_timestamp
            , v_column_list);

        -- Set analyze to true if a table is created
        v_analyze := @extschema@.create_partition_time(p_parent_table, v_partition_timestamp);

        EXECUTE format('WITH partition_data AS (
                DELETE FROM partman_temp_data_storage RETURNING *)
            INSERT INTO %I.%I (%3$s) SELECT %3$s FROM partition_data'
            , v_parent_schema
            , v_current_partition_name
            , v_column_list);

    ELSE

        -- Set analyze to true if a table is created
        v_analyze := @extschema@.create_partition_time(p_parent_table, v_partition_timestamp);

        EXECUTE format('WITH partition_data AS (
                            DELETE FROM ONLY %I.%I WHERE %s >= %L AND %3$s < %5$L RETURNING *)
                         INSERT INTO %6$I.%7$I (%8$s) SELECT %8$s FROM partition_data'
                            , v_source_schemaname
                            , v_source_tablename
                            , v_partition_expression
                            , v_min_partition_timestamp
                            , v_max_partition_timestamp
                            , v_parent_schema
                            , v_current_partition_name
                            , v_column_list);
    END IF;

    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    v_total_rows := v_total_rows + v_rowcount;
    IF v_rowcount = 0 THEN
        EXIT;
    END IF;

END LOOP;

-- v_analyze is a local check if a new table is made.
-- p_analyze is a parameter to say whether to run the analyze at all. Used by create_parent() to avoid long exclusive lock or run_maintenence() to avoid long creation runs.
IF v_analyze AND p_analyze THEN
    RAISE DEBUG 'partiton_data_time: Begin analyze of %.%', v_parent_schema, v_parent_tablename;
    EXECUTE format('ANALYZE %I.%I', v_parent_schema, v_parent_tablename);
    RAISE DEBUG 'partiton_data_time: End analyze of %.%', v_parent_schema, v_parent_tablename;
END IF;

RETURN v_total_rows;

END
$$;


CREATE FUNCTION @extschema@.inherit_replica_identity (p_parent_schemaname text, p_parent_tablename text, p_child_tablename text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE

v_parent_oid                    oid;
v_parent_replident              char;
v_parent_replident_index        name;
v_replident_string              text;
v_sql                           text;

BEGIN

/*
* Set the given child table's replica idenitity to the same as the parent
 NOTE: Replication identity not automatically inherited as of PG16 (revisit in future versions)
*/

SELECT c.oid
    , c.relreplident
INTO v_parent_oid
    , v_parent_replident
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = p_parent_schemaname
AND c.relname = p_parent_tablename;

IF v_parent_replident = 'i' THEN
    SELECT c.relname
    INTO v_parent_replident_index
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_index i ON i.indexrelid = c.oid
    WHERE i.indrelid = v_parent_oid
    AND indisreplident;
END IF;

RAISE DEBUG 'inherit_replica_ident: v_parent_oid: %, v_parent_replident: %,  v_parent_replident_index: %', v_parent_oid, v_parent_replident,  v_parent_replident_index;

IF v_parent_replident != 'd' THEN
    CASE v_parent_replident
        WHEN 'f' THEN v_replident_string := 'FULL';
        WHEN 'i' THEN v_replident_string := format('USING INDEX %I', v_parent_replident_index);
        WHEN 'n' THEN v_replident_string := 'NOTHING';
    ELSE
        RAISE EXCEPTION 'inherit_replica_identity: Unknown replication identity encountered (%). Please report as a bug on pg_partman''s github', v_parent_replident;
    END CASE;
    v_sql := format('ALTER TABLE %I.%I REPLICA IDENTITY %s'
                    , p_parent_schemaname
                    , p_child_tablename
                    , v_replident_string);
    RAISE DEBUG 'inherit_replica_identity: replident v_sql: %', v_sql;
    EXECUTE v_sql;
END IF;

END
$$;

-- Restore dropped object privileges
DO $$
DECLARE
v_row   record;
BEGIN
    FOR v_row IN SELECT statement FROM partman_preserve_privs_temp LOOP
        IF v_row.statement IS NOT NULL THEN
            EXECUTE v_row.statement;
        END IF;
    END LOOP;
END
$$;

DROP TABLE IF EXISTS partman_preserve_privs_temp;
