
-- TODO After copying changed objects to their file, check that `create_parent` didn't get inadvertently removed anywhere else due to stupid find and replace run
-- check everywhere for create_parent and create_sub_parent
    -- Update most tests with new names but leave some with old for code coverage


CREATE TEMP TABLE partman_preserve_privs_temp (statement text);

INSERT INTO partman_preserve_privs_temp
SELECT 'GRANT EXECUTE ON PROCEDURE @extschema@.reapply_constraints_proc(text, boolean, boolean, boolean, int, boolean)  TO '||array_to_string(array_agg('"'||grantee::text||'"'), ',')||';'
FROM information_schema.routine_privileges
WHERE routine_schema = '@extschema@'
AND routine_name = 'reapply_constraints_proc'
AND grantee != 'PUBLIC';

INSERT INTO partman_preserve_privs_temp
SELECT 'GRANT EXECUTE ON FUNCTION @extschema@.partition_data_time(text, int, interval, numeric, text, boolean, text, text[], boolean, boolean) TO '||array_to_string(array_agg('"'||grantee::text||'"'), ',')||';'
FROM information_schema.routine_privileges
WHERE routine_schema = '@extschema@'
AND routine_name = 'partition_data_time'
AND grantee != 'PUBLIC';

INSERT INTO partman_preserve_privs_temp
SELECT 'GRANT EXECUTE ON PROCEDURE @extschema@.partition_data_proc (text, int, text, int, int, int, text, text, text[], boolean, boolean) TO '||array_to_string(array_agg('"'||grantee::text||'"'), ',')||';'
FROM information_schema.routine_privileges
WHERE routine_schema = '@extschema@'
AND routine_name = 'partition_data_proc'
AND grantee != 'PUBLIC';

/* Apply privileges from old create_parent functions to the new ones */
INSERT INTO partman_preserve_privs_temp
SELECT 'GRANT EXECUTE ON FUNCTION @extschema@.create_partition (text, text, text, text, text, int, text, boolean, text, text[], text, boolean, text, boolean, text, text, bigint) TO '||array_to_string(array_agg('"'||grantee::text||'"'), ',')||';'
FROM information_schema.routine_privileges
WHERE routine_schema = '@extschema@'
AND routine_name = 'create_parent'
AND grantee != 'PUBLIC';

INSERT INTO partman_preserve_privs_temp
SELECT 'GRANT EXECUTE ON FUNCTION @extschema@.create_sub_partition (text, text, text, text, boolean, text, text[], int, text, text, boolean, text, boolean, text, text) TO '||array_to_string(array_agg('"'||grantee::text||'"'), ',')||';'
FROM information_schema.routine_privileges
WHERE routine_schema = '@extschema@'
AND routine_name = 'create_sub_parent'
AND grantee != 'PUBLIC';


DROP PROCEDURE @extschema@.reapply_constraints_proc(text, boolean, boolean, int, boolean);
DROP FUNCTION @extschema@.partition_data_time(text, int, interval, numeric, text, boolean, text, text[], boolean);
DROP FUNCTION @extschema@.check_default(boolean);
DROP PROCEDURE @extschema@.partition_data_proc (text, int, text, int, int, int, text, text, text[], boolean);

CREATE PROCEDURE @extschema@.reapply_constraints_proc(
    p_parent_table text
    , p_drop_constraints boolean DEFAULT false
    , p_apply_constraints boolean DEFAULT false
    , p_analyze boolean DEFAULT true
    , p_wait int DEFAULT 0
    , p_dryrun boolean DEFAULT false
)
    LANGUAGE plpgsql
    AS $$
DECLARE

v_adv_lock                      boolean;
v_child_exists                  text;
v_child_stop                    text;
v_child_value                   text;
v_control                       text;
v_control_type                  text;
v_datetime_string               text;
v_epoch                         text;
v_last_partition                text;
v_last_partition_id             bigint;
v_last_partition_timestamp      timestamptz;
v_optimize_constraint           int;
v_optimize_counter              int := 0;
v_parent_schema                 text;
v_parent_tablename              text;
v_partition_interval            text;
v_partition_suffix              text;
v_premake                       int;
v_row                           record;
v_row_max_value                 record;
v_sql                           text;

BEGIN
/*
 * Procedure for reapplying additional constraints managed by pg_partman on child tables. See docs for additional info on this special constraint management.
 * Procedure can run in two distinct modes: 1) Drop all constraints  2) Apply all constraints.
 * If both modes are run in a single call, drop is run before apply.
 * Typical usage would be to run the drop mode, edit the data, then run apply mode to re-create all constraints on a partition set."
 */

v_adv_lock := pg_try_advisory_lock(hashtext('pg_partman reapply_constraints'));
IF v_adv_lock = false THEN
    RAISE NOTICE 'Partman reapply_constraints_proc already running or another session has not released its advisory lock.';
    RETURN;
END IF;


SELECT control, premake, optimize_constraint, datetime_string, epoch, partition_interval
INTO v_control, v_premake, v_optimize_constraint, v_datetime_string, v_epoch, v_partition_interval
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;
IF v_premake IS NULL THEN
    RAISE EXCEPTION 'Unable to find given parent in pg_partman config: %. This procedure is only meant to be called on pg_partman managed partition sets.', p_parent_table;
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

-- Determine child table to stop creating constraints on based on optimize_constraint value
-- Same code in apply_constraints.sql
SELECT partition_tablename INTO v_last_partition FROM @extschema@.show_partitions(p_parent_table, 'DESC', false) LIMIT 1;

FOR v_row_max_value IN
    SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(p_parent_table, 'DESC', false)
LOOP
    IF v_child_value IS NULL THEN
        EXECUTE format('SELECT %L::text FROM %I.%I LIMIT 1'
                            , v_control
                            , v_row_max_value.partition_schemaname
                            , v_row_max_value.partition_tablename
                        ) INTO v_child_value;

    ELSE
        v_optimize_counter := v_optimize_counter + 1;
        IF v_optimize_counter = v_optimize_constraint THEN
            v_child_stop = v_row_max_value.partition_tablename;
            EXIT;
        END IF;
    END IF;
END LOOP;

IF v_optimize_counter < v_optimize_constraint THEN
    -- No child table exists that is old enough to apply constraints
    RAISE DEBUG 'reapply_constraint: Target child stop table not found. Skipping all constraint creation.';
    RETURN;
END IF;

v_sql := format('SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(%L, %L)', p_parent_table, 'ASC');

RAISE DEBUG 'reapply_constraint: v_parent_tablename: % , v_partition_suffix: %, v_child_stop: %,  v_sql: %', v_parent_tablename, v_partition_suffix, v_child_stop, v_sql;

v_row := NULL;
FOR v_row IN EXECUTE v_sql LOOP
    IF p_drop_constraints THEN
        IF p_dryrun THEN
            RAISE NOTICE 'DRYRUN NOTICE: Dropping constraints on child table: %.%', v_row.partition_schemaname, v_row.partition_tablename;
        ELSE
            RAISE DEBUG 'reapply_constraint drop: %.%', v_row.partition_schemaname, v_row.partition_tablename;
            PERFORM @extschema@.drop_constraints(p_parent_table, format('%s.%s', v_row.partition_schemaname, v_row.partition_tablename)::text);
        END IF;
    END IF; -- end drop
    COMMIT;

    IF p_apply_constraints THEN
        IF p_dryrun THEN
            RAISE NOTICE 'DRYRUN NOTICE: Applying constraints on child table: %.%', v_row.partition_schemaname, v_row.partition_tablename;
        ELSE
            RAISE DEBUG 'reapply_constraint apply: %.%', v_row.partition_schemaname, v_row.partition_tablename;
            PERFORM @extschema@.apply_constraints(p_parent_table, format('%s.%s', v_row.partition_schemaname, v_row.partition_tablename)::text);
        END IF;
    END IF; -- end apply
    COMMIT;

    IF v_row.partition_tablename = v_child_stop THEN
        RAISE DEBUG 'reapply_constraint: Reached stop at %.%', v_row.partition_schemaname, v_row.partition_tablename;
        EXIT; -- stop creating constraints after optimize target is reached
    END IF;
    PERFORM pg_sleep(p_wait);
END LOOP;

IF p_analyze THEN
    IF p_dryrun THEN
        RAISE NOTICE 'ANALYZE %.%', v_parent_schema, v_parent_tablename;
    ELSE
        EXECUTE format('ANALYZE %I.%I', v_parent_schema, v_parent_tablename);
    END IF;
END IF;

PERFORM pg_advisory_unlock(hashtext('pg_partman reapply_constraints'));
END
$$;


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
    , p_control_not_null boolean DEFAULT true
    , p_time_encoder text DEFAULT NULL
    , p_time_decoder text DEFAULT NULL
    , p_offset_id bigint DEFAULT 0
)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE

BEGIN
/*
    This is an alias function for create_partition() for backward compatibility
*/

RETURN @extschema@.create_partition(
    p_parent_table
    , p_control
    , p_interval
    , p_type
    , p_epoch
    , p_premake
    , p_start_partition
    , p_default_table
    , p_automatic_maintenance
    , p_constraint_cols
    , p_template_table
    , p_jobmon
    , p_date_trunc_interval
    , p_control_not_null
    , p_time_encoder
    , p_time_decoder
    , p_offset_id
);

END
$$;


CREATE FUNCTION @extschema@.create_partition(
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
    , p_control_not_null boolean DEFAULT true
    , p_time_encoder text DEFAULT NULL
    , p_time_decoder text DEFAULT NULL
    , p_offset_id bigint DEFAULT 0
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
v_parent_schemaname                 text;
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
 * IMPORTANT: Do not forget to update parameters for create_parent() if they change in this function
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
    , t.spcname
INTO v_parent_schemaname
    , v_parent_tablename
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
AND n.nspname = v_parent_schemaname::name
AND a.attname = p_control::name;
    IF (v_notnull IS NULL) THEN
        RAISE EXCEPTION 'Control column given (%) for parent table (%) does not exist', p_control, p_parent_table;
    ELSIF (v_notnull = false and p_control_not_null = true) THEN
        RAISE EXCEPTION 'Control column given (%) for parent table (%) must be set to NOT NULL', p_control, p_parent_table;
    END IF;

SELECT general_type, exact_type INTO v_control_type, v_control_exact_type
FROM @extschema@.check_control_type(v_parent_schemaname, v_parent_tablename, p_control);

IF v_control_type IS NULL THEN
    RAISE EXCEPTION 'pg_partman only supports partitioning of data types that are integer, numeric, date/timestamp or specially encoded text. Supplied column is of type %', v_control_exact_type;
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
WHERE n.nspname = v_parent_schemaname::name
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
WHERE n.nspname = v_parent_schemaname::name
AND c.relname = v_parent_tablename::name
AND attnum IN (SELECT unnest(partattrs) FROM pg_partitioned_table p WHERE a.attrelid = p.partrelid);

IF p_control <> v_part_col OR v_control_exact_type <> v_part_type THEN
    RAISE EXCEPTION 'Control column and type given in arguments (%, %) does not match the control column and type of the given partition set (%, %)', p_control, v_control_exact_type, v_part_col, v_part_type;
END IF;

-- Check that control column is a usable type for pg_partman.
IF v_control_type NOT IN ('time', 'id', 'text', 'uuid') THEN
    RAISE EXCEPTION 'Only date/time, text/uuid or integer types are allowed for the control column.';
ELSIF v_control_type IN ('text', 'uuid') AND (p_time_encoder IS NULL OR p_time_decoder IS NULL) THEN
    RAISE EXCEPTION 'p_time_encoder and p_time_decoder needs to be set for text/uuid type control column.';
ELSIF v_control_type NOT IN ('text', 'uuid') AND (p_time_encoder IS NOT NULL OR p_time_decoder IS NOT NULL) THEN
    RAISE EXCEPTION 'p_time_encoder and p_time_decoder can only be used with text/uuid type control column.';
END IF;

-- Table to handle properties not managed by core PostgreSQL yet
IF p_template_table IS NULL THEN
    v_template_schema := '@extschema@';
    v_template_tablename := @extschema@.check_name_length('template_'||v_parent_schemaname||'_'||v_parent_tablename);
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I.%I (LIKE %I.%I)', v_template_schema, v_template_tablename, v_parent_schemaname, v_parent_tablename);

    SELECT pg_get_userbyid(c.relowner) INTO v_parent_owner
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = v_parent_schemaname::name
    AND c.relname = v_parent_tablename::name;

    EXECUTE format('ALTER TABLE %s.%I OWNER TO %I'
            , '@extschema@'
            , v_template_tablename
            , v_parent_owner);
ELSIF lower(p_template_table) IN ('false', 'f') THEN
    v_template_schema := NULL;
    v_template_tablename := NULL;
    RAISE DEBUG 'create_partition(): parent_table: %, skipped template table creation', p_parent_table;
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

EXECUTE format('LOCK TABLE %I.%I IN ACCESS EXCLUSIVE MODE', v_parent_schemaname, v_parent_tablename);

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
        AND n.nspname = v_parent_schemaname::name
    ), sibling_children AS (
        SELECT i.inhrelid::regclass::text AS tablename
        FROM pg_inherits i
        JOIN parent_table p ON i.inhparent = p.parent_oid
    )
    -- This column list must be kept consistent between:
    --   , check_subpart_sameconfig, create_partition_id, create_partition_time, dump_partitioned_table_definition and table definition
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

IF v_control_type IN ('time', 'text', 'uuid') OR (v_control_type = 'id' AND p_epoch <> 'none') THEN

    v_time_interval := p_interval::interval;
    IF v_time_interval < '1 second'::interval THEN
        RAISE EXCEPTION 'Partitioning interval must be 1 second or greater';
    END IF;

   -- First partition is either the min premake or p_start_partition
    v_start_time := COALESCE(p_start_partition::timestamptz, CURRENT_TIMESTAMP - (v_time_interval * p_premake));

    SELECT base_timestamp, datetime_string
    INTO v_base_timestamp, v_datetime_string
    FROM @extschema@.calculate_time_partition_info(v_time_interval, v_start_time, p_date_trunc_interval);

    RAISE DEBUG '(): parent_table: %, v_base_timestamp: %', p_parent_table, v_base_timestamp;

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
        , time_encoder
        , time_decoder
        , constraint_cols
        , datetime_string
        , automatic_maintenance
        , jobmon
        , template_table
        , inherit_privileges
        , date_trunc_interval)
    VALUES (
        p_parent_table
        , p_type
        , v_time_interval
        , p_epoch
        , p_control
        , p_premake
        , p_time_encoder
        , p_time_decoder
        , p_constraint_cols
        , v_datetime_string
        , p_automatic_maintenance
        , p_jobmon
        , v_template_schema||'.'||v_template_tablename
        , v_inherit_privileges
        , p_date_trunc_interval);

    RAISE DEBUG ': v_partition_time_array: %', v_partition_time_array;

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
            AND n.nspname = v_parent_schemaname::name
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

    v_starting_partition_id := ((v_max - (v_max % v_id_interval)) + p_offset_id);
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
            AND n.nspname = v_parent_schemaname::name
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

    -- Same INCLUDING list is used in create_partition_*(). INDEXES is handled when partition is attached if it's supported.
    v_sql := v_sql || format(' TABLE IF NOT EXISTS %I.%I (LIKE %I.%I INCLUDING COMMENTS INCLUDING COMPRESSION INCLUDING CONSTRAINTS INCLUDING DEFAULTS INCLUDING GENERATED INCLUDING STATISTICS INCLUDING STORAGE)'
        , v_parent_schemaname, v_default_partition, v_parent_schemaname, v_parent_tablename);
    IF v_parent_tablespace IS NOT NULL THEN
        v_sql := format('%s TABLESPACE %I ', v_sql, v_parent_tablespace);
    END IF;
    EXECUTE v_sql;

    v_sql := format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I DEFAULT'
        , v_parent_schemaname, v_parent_tablename, v_parent_schemaname, v_default_partition);
    EXECUTE v_sql;

    PERFORM @extschema@.inherit_replica_identity(v_parent_schemaname, v_parent_tablename, v_default_partition);

    -- Manage template inherited properties
    IF v_template_tablename IS NOT NULL THEN
        PERFORM @extschema@.inherit_template_properties(p_parent_table, v_parent_schemaname, v_default_partition);
    END IF;

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


CREATE PROCEDURE @extschema@.partition_data_proc (
    p_parent_table text
    , p_loop_count int DEFAULT NULL
    , p_interval text DEFAULT NULL
    , p_lock_wait int DEFAULT 0
    , p_lock_wait_tries int DEFAULT 10
    , p_wait int DEFAULT 1
    , p_order text DEFAULT 'ASC'
    , p_source_table text DEFAULT NULL
    , p_ignored_columns text[] DEFAULT NULL
    , p_quiet boolean DEFAULT false
    , p_ignore_infinity boolean DEFAULT false
)
    LANGUAGE plpgsql
    AS $$
DECLARE

v_adv_lock          boolean;
v_control           text;
v_control_type      text;
v_epoch             text;
v_is_autovac_off    boolean := false;
v_lockwait_count    int := 0;
v_loop_count        int := 0;
v_parent_schemaname     text;
v_parent_tablename  text;
v_rows_moved        bigint;
v_source_schemaname     text;
v_source_tablename  text;
v_sql               text;
v_total             bigint := 0;

BEGIN

v_adv_lock := pg_try_advisory_lock(hashtext('pg_partman partition_data_proc'), hashtext(p_parent_table));
IF v_adv_lock = 'false' THEN
    RAISE NOTICE 'Advisory lock notice (pg_partman partition_data_proc): This procedure is already running for given parent table (%) or another session has not released its advisory lock.', p_parent_table;
    RETURN;
END IF;

SELECT control, epoch
INTO v_control, v_epoch
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;
IF NOT FOUND THEN
    RAISE EXCEPTION 'ERROR: No entry in part_config found for given table: %', p_parent_table;
END IF;

SELECT n.nspname, c.relname INTO v_parent_schemaname, v_parent_tablename
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_parent_table, '.', 1)::name
AND c.relname = split_part(p_parent_table, '.', 2)::name;
    IF v_parent_tablename IS NULL THEN
        RAISE EXCEPTION 'Unable to find given parent table in system catalogs. Ensure it is schema qualified: %', p_parent_table;
    END IF;

IF p_source_table IS NOT NULL THEN
    SELECT n.nspname, c.relname INTO v_source_schemaname, v_source_tablename
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = split_part(p_source_table, '.', 1)::name
    AND c.relname = split_part(p_source_table, '.', 2)::name;
        IF v_source_tablename IS NULL THEN
            RAISE EXCEPTION 'Unable to find given source table in system catalogs. Ensure it is schema qualified: %', p_source_table;
        END IF;
END IF;

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_parent_schemaname, v_parent_tablename, v_control);

IF v_control_type = 'id' AND v_epoch <> 'none' THEN
        v_control_type := 'time';
END IF;

/*
-- Currently no way to catch exception and reset autovac settings back to normal. Until I can do that, leaving this feature out for now
-- Leaving the functions to turn off/reset in to let people do that manually if desired
IF p_autovacuum_on = false THEN         -- Add this parameter back to definition when this is working
    -- Turn off autovac for parent, source table if set, and all child tables
    v_is_autovac_off := @extschema@.autovacuum_off(v_parent_schemaname, v_parent_tablename, v_source_schema, v_source_tablename);
    COMMIT;
END IF;
*/

v_sql := format('SELECT %s.partition_data_%s (p_parent_table := %L
                                                , p_lock_wait := %L
                                                , p_order := %L
                                                , p_analyze := false'
        , '@extschema@', v_control_type, p_parent_table, p_lock_wait, p_order, p_ignore_infinity);
IF p_interval IS NOT NULL THEN
    v_sql := v_sql || format(', p_batch_interval := %L', p_interval);
END IF;
IF p_source_table IS NOT NULL THEN
    v_sql := v_sql || format(', p_source_table := %L', p_source_table);
END IF;
IF p_ignored_columns IS NOT NULL THEN
    v_sql := v_sql || format(', p_ignored_columns := %L', p_ignored_columns);
END IF;
IF v_control_type = 'time' THEN
    v_sql := v_sql || format(', p_ignore_infinity := %L', p_ignore_infinity);
END IF;
v_sql := v_sql || ')';
RAISE DEBUG 'partition_data sql: %', v_sql;

LOOP
    EXECUTE v_sql INTO v_rows_moved;
    -- If lock wait timeout, do not increment the counter
    IF v_rows_moved != -1 THEN
        v_loop_count := v_loop_count + 1;
        v_total := v_total + v_rows_moved;
        v_lockwait_count := 0;
    ELSE
        v_lockwait_count := v_lockwait_count + 1;
        IF v_lockwait_count > p_lock_wait_tries THEN
            RAISE EXCEPTION 'Quitting due to inability to get lock on next batch of rows to be moved';
        END IF;
    END IF;
    IF p_quiet = false THEN
        IF v_rows_moved > 0 THEN
            RAISE NOTICE 'Loop: %, Rows moved: %', v_loop_count, v_rows_moved;
        ELSIF v_rows_moved = -1 THEN
            RAISE NOTICE 'Unable to obtain row locks for data to be moved. Trying again...';
        END IF;
    END IF;
    -- If no rows left or given loop argument limit is reached
    IF v_rows_moved = 0 OR (p_loop_count > 0 AND v_loop_count >= p_loop_count) THEN
        EXIT;
    END IF;
    COMMIT;
    PERFORM pg_sleep(p_wait);
    RAISE DEBUG 'v_rows_moved: %, v_loop_count: %, v_total: %, v_lockwait_count: %, p_wait: %', p_wait, v_rows_moved, v_loop_count, v_total, v_lockwait_count;
END LOOP;

/*
IF v_is_autovac_off = true THEN
    -- Reset autovac back to default if it was turned off by this procedure
    PERFORM @extschema@.autovacuum_reset(v_parent_schemaname, v_parent_tablename, v_source_schema, v_source_tablename);
    COMMIT;
END IF;
*/

IF p_quiet = false THEN
    RAISE NOTICE 'Total rows moved: %', v_total;
END IF;
RAISE NOTICE 'Ensure to VACUUM ANALYZE the parent (and source table if used) after partitioning data';

/* Leaving here until I can figure out what's wrong with procedures and exception handling
EXCEPTION
    WHEN QUERY_CANCELED THEN
        ROLLBACK;
        -- Reset autovac back to default if it was turned off by this procedure
        IF v_is_autovac_off = true THEN
            PERFORM @extschema@.autovacuum_reset(v_parent_schema, v_parent_tablename, v_source_schema, v_source_tablename);
        END IF;
        RAISE EXCEPTION '%', SQLERRM;
    WHEN OTHERS THEN
        ROLLBACK;
        -- Reset autovac back to default if it was turned off by this procedure
        IF v_is_autovac_off = true THEN
            PERFORM @extschema@.autovacuum_reset(v_parent_schema, v_parent_tablename, v_source_schema, v_source_tablename);
        END IF;
        RAISE EXCEPTION '%', SQLERRM;
*/

PERFORM pg_advisory_unlock(hashtext('pg_partman partition_data_proc'), hashtext(p_parent_table));
END;
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

v_adv_lock := pg_try_advisory_lock(hashtext('pg_partman run_maintenance_proc'));
IF v_adv_lock = false THEN
    RAISE NOTICE 'Advisory lock notice (pg_partman run_maintenance_proc): Partman maintenance procedure already running or another session has not released its advisory lock.';
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

PERFORM pg_advisory_unlock(hashtext('pg_partman run_maintenance_proc'));
END
$$;


CREATE FUNCTION @extschema@.config_cleanup(
    p_parent_table text
    , p_config_table boolean DEFAULT true
    , p_config_sub_table boolean DEFAULT true
    , p_template_table boolean DEFAULT true
)
    RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE

v_parent_table              text;
v_template_schemaname       text;
v_template_table            text;
v_template_tablename        text;
v_rowcount                  int = 0;

BEGIN

SELECT parent_table
INTO v_parent_table
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;

IF v_parent_table IS NULL THEN
    RAISE EXCEPTION 'No configuration found in pg_partman for given parent table: %', p_parent_table;
END IF;

IF p_template_table THEN

    SELECT template_table
    INTO v_template_table
    FROM @extschema@.part_config
    WHERE parent_table = p_parent_table;

    IF v_template_table IS NULL THEN
        RAISE NOTICE 'No template table found in part_config for given parent table (%)', v_parent_table;
    ELSE
        SELECT n.nspname
            , c.relname
        INTO v_template_schemaname
            , v_template_tablename
        FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = split_part(v_template_table, '.', 1)::name
        AND c.relname = split_part(v_template_table, '.', 2)::name;

        IF v_template_tablename IS NULL THEN
            RAISE WARNING 'Template table in part_config (%) for given parent table (%) does not exist in the PostgreSQL catalog.', v_template_table, p_parent_table;
        ELSE
            EXECUTE format('DROP TABLE %I.%I', v_template_schemaname, v_template_tablename);
            RAISE NOTICE 'Dropped template table: %', v_template_table;
        END IF;

    END IF;

END IF;

IF p_config_table THEN
    DELETE FROM @extschema@.part_config WHERE parent_table = p_parent_table;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount > 0 THEN
        RAISE NOTICE 'Configuration for given table (%) successfully removed from part_config table.', p_parent_table;
    ELSE
        RAISE NOTICE 'No configuration for given table (%) found in part_config.', p_parent_table;
    END IF;
END IF;

v_rowcount = 0;

IF p_config_sub_table THEN
    DELETE FROM @extschema@.part_config_sub WHERE sub_parent = p_parent_table;
    GET DIAGNOSTICS v_rowcount = ROW_COUNT;
    IF v_rowcount > 0 THEN
        RAISE NOTICE 'Configuration for given table (%) successfully removed from part_config_sub table.', p_parent_table;
    ELSE
        RAISE NOTICE 'No configuration for given table (%) found in part_config_sub.', p_parent_table;
    END IF;
END IF;

END
$$;


CREATE FUNCTION @extschema@.partition_data_time(
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
    AS $$
DECLARE

v_analyze                   boolean := FALSE;
v_async_rowcount            int;
v_column_list_filtered      text;
v_column_list_full          text;
v_control                   text;
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

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_parent_schemaname, v_parent_tablename, v_control);
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
        v_decoded_col := format('%s::text', v_partition_expression);
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


CREATE OR REPLACE FUNCTION @extschema@.partition_data_id(
    p_parent_table text
    , p_batch_count int DEFAULT 1
    , p_batch_interval bigint DEFAULT NULL
    , p_lock_wait numeric DEFAULT 0
    , p_order text DEFAULT 'ASC'
    , p_analyze boolean DEFAULT true
    , p_source_table text DEFAULT NULL
    , p_ignored_columns text[] DEFAULT NULL
    , p_override_system_value boolean DEFAULT false
)
    RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE

v_analyze                   boolean := FALSE;
v_column_list_filtered      text;
v_column_list_full          text;
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
v_override_statement        text;
v_parent_schemaname         text;
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

SELECT schemaname, tablename INTO v_parent_schemaname, v_parent_tablename
FROM pg_catalog.pg_tables
WHERE schemaname = split_part(p_parent_table, '.', 1)::name
AND tablename = split_part(p_parent_table, '.', 2)::name;

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_parent_schemaname, v_parent_tablename, v_control);

IF v_control_type <> 'id' OR (v_control_type = 'id' AND v_epoch <> 'none') THEN
    RAISE EXCEPTION 'Control column for given partition set is not id/serial based or epoch flag is set for time-based partitioning.';
END IF;

SELECT n.nspname::text, c.relname::text
INTO v_default_schemaname, v_default_tablename
FROM pg_catalog.pg_inherits h
JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE h.inhparent = format('%I.%I', v_parent_schemaname, v_parent_tablename)::regclass
AND pg_get_expr(relpartbound, c.oid) = 'DEFAULT';

IF p_source_table IS NOT NULL THEN

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
        RAISE EXCEPTION 'If any interval smaller than the partition interval must be used for moving data out of the default, please use the partition_data_async() procedure.';
    END IF;

    -- Set source table to default table if p_source_table is not set, and it exists
    -- Otherwise just return with a NOTICE that no data source exists

    IF v_default_tablename IS NOT NULL THEN
        v_source_schemaname := v_default_schemaname;
        v_source_tablename := v_default_tablename;

        v_default_exists := true;
        EXECUTE format ('CREATE TEMP TABLE IF NOT EXISTS partman_temp_data_storage (LIKE %I.%I INCLUDING DEFAULTS INCLUDING INDEXES) ON COMMIT DROP', v_source_schemaname, v_source_tablename);
    ELSE
        RAISE NOTICE 'No default table found when partition_data_id() was called';
        RETURN v_total_rows;
    END IF;

END IF;

IF p_batch_interval IS NULL OR p_batch_interval > v_partition_interval THEN
    p_batch_interval := v_partition_interval;
END IF;

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

FOR i IN 1..p_batch_count LOOP

    IF p_order = 'ASC' THEN
        EXECUTE format('SELECT min(%I) FROM ONLY %I.%I', v_control, v_source_schemaname, v_source_tablename) INTO v_start_control;
        IF v_start_control IS NULL THEN
            EXIT;
        END IF;
        v_min_partition_id := v_start_control - (v_start_control % v_partition_interval);
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
        v_min_partition_id := v_start_control - (v_start_control % v_partition_interval);
        -- Must be greater than max value still in parent table since query below grabs < max
        v_max_partition_id := v_min_partition_id + v_partition_interval;
        v_partition_id := ARRAY[v_min_partition_id];
        -- Make sure minimum doesn't underflow current partition minimum
        IF (v_start_control - p_batch_interval) >= v_min_partition_id THEN
            v_min_partition_id := v_start_control - p_batch_interval;
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
                v_sql := format('SELECT * FROM ONLY %I.%I WHERE %I >= %s AND %I < %s FOR UPDATE NOWAIT'
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

    IF p_override_system_value THEN
        v_override_statement = ' OVERRIDING SYSTEM VALUE ';
    ELSE
        v_override_statement = ' ';
    END IF;

    IF v_default_exists THEN

        -- Child tables cannot be created if data that belongs to it exists in the default
        -- Have to move data out to temporary location, create child table, then move it back

        -- Temp table created above to avoid excessive temp creation in loop
        -- Must use full column list here since the temp table cannot have generated/identity values for defaults.
        --      This allows for all scenarios where some people may want newly generated values and others may not.
        --      Those that want them are handled by the filtered column list when moving to the real table
        EXECUTE format('WITH partition_data AS (
                DELETE FROM %1$I.%2$I WHERE %3$I >= %4$s AND %3$I < %5$s RETURNING *)
            INSERT INTO partman_temp_data_storage (%6$s) SELECT %6$s FROM partition_data'
            , v_source_schemaname
            , v_source_tablename
            , v_control
            , v_min_partition_id
            , v_max_partition_id
            , v_column_list_full);

        -- Set analyze to true if a table is created
        v_analyze := @extschema@.create_partition_id(p_parent_table, v_partition_id);

        EXECUTE format('WITH partition_data AS (
                DELETE FROM partman_temp_data_storage RETURNING *)
            INSERT INTO %1$I.%2$I (%3$s) %4$s SELECT %3$s FROM partition_data'
            , v_parent_schemaname
            , v_current_partition_name
            , v_column_list_filtered
            , v_override_statement);

    ELSE

        -- Set analyze to true if a table is created
        v_analyze := @extschema@.create_partition_id(p_parent_table, v_partition_id);

        EXECUTE format('WITH partition_data AS (
                DELETE FROM ONLY %1$I.%2$I WHERE %3$I >= %4$s AND %3$I < %5$s RETURNING *)
            INSERT INTO %6$I.%7$I (%8$s) %9$s SELECT %8$s FROM partition_data'
            , v_source_schemaname
            , v_source_tablename
            , v_control
            , v_min_partition_id
            , v_max_partition_id
            , v_parent_schemaname
            , v_current_partition_name
            , v_column_list_filtered
            , v_override_statement);

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


CREATE FUNCTION @extschema@.check_default(
        p_exact_count boolean DEFAULT true
        , p_ignore_infinity boolean DEFAULT false)
    RETURNS SETOF @extschema@.check_default_table
    LANGUAGE plpgsql STABLE
    SET search_path = @extschema@,pg_temp
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


CREATE OR REPLACE FUNCTION @extschema@.apply_privileges(p_parent_schema text, p_parent_tablename text, p_child_schema text, p_child_tablename text, p_job_id bigint DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE

ex_context          text;
ex_detail           text;
ex_hint             text;
ex_message          text;
v_all               text[];
v_child_grant       record;
v_child_owner       text;
v_grantees          text[];
v_job_id            bigint;
v_jobmon            boolean;
v_jobmon_schema     text;
v_match             boolean;
v_parent_grant      record;
v_parent_owner      text;
v_revoke            text;
v_row_revoke        record;
v_sql               text;
v_step_id           bigint;

BEGIN
/*
 * Apply privileges and ownership that exist on a given parent to the given child table
 */

/* init v_all to a list of all table-related privileges available to current user */
v_all := array(select (aclexplode(acldefault('r'::"char", usesysid))).privilege_type from pg_catalog.pg_user pu where pu.usename = current_user);

SELECT jobmon INTO v_jobmon FROM @extschema@.part_config WHERE parent_table = p_parent_schema ||'.'|| p_parent_tablename;
IF v_jobmon IS NULL THEN
    RAISE EXCEPTION 'Given table is not managed by this extension: %.%', p_parent_schema, p_parent_tablename;
END IF;

SELECT pg_get_userbyid(c.relowner) INTO v_parent_owner
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = p_parent_schema::name
AND c.relname = p_parent_tablename::name;

SELECT pg_get_userbyid(c.relowner) INTO v_child_owner
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = p_child_schema::name
AND c.relname = p_child_tablename::name;

IF v_parent_owner IS NULL THEN
    RAISE EXCEPTION 'Given parent table does not exist: %.%', p_parent_schema, p_parent_tablename;
END IF;
IF v_child_owner IS NULL THEN
    RAISE EXCEPTION 'Given child table does not exist: %.%', p_child_schema, p_child_tablename;
END IF;

IF v_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_namespace n, pg_extension e WHERE e.extname = 'pg_jobmon' AND e.extnamespace = n.oid;
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    IF p_job_id IS NULL THEN
        EXECUTE format('SELECT %I.add_job(%L)', v_jobmon_schema, format('PARTMAN APPLYING PRIVILEGES TO CHILD TABLE: %s.%s', p_child_schema, p_child_tablename)) INTO v_job_id;
    ELSE
        v_job_id := p_job_id;
    END IF;
    EXECUTE format('SELECT %I.add_step(%L, %L)', v_jobmon_schema, v_job_id, format('Setting new child table privileges for %s.%s', p_child_schema, p_child_tablename)) INTO v_step_id;
END IF;

IF v_jobmon_schema IS NOT NULL THEN

    EXECUTE format('SELECT %I.update_step(%L, %L, %L)'
            , v_jobmon_schema
            , v_step_id
            , 'PENDING'
            , format('Applying privileges on child partition: %s.%s'
                , p_child_schema
                , p_child_tablename)
            );
END IF;

FOR v_parent_grant IN
    SELECT array_agg(DISTINCT privilege_type::text ORDER BY privilege_type::text) AS types
            , grantee
    FROM @extschema@.table_privs
    WHERE table_schema = p_parent_schema::name AND table_name = p_parent_tablename::name
    GROUP BY grantee
LOOP
    -- Compare parent & child grants. Don't re-apply if it already exists
    v_match := false;
    v_sql := NULL;
    FOR v_child_grant IN
        SELECT array_agg(DISTINCT privilege_type::text ORDER BY privilege_type::text) AS types
                , grantee
        FROM @extschema@.table_privs
        WHERE table_schema = p_child_schema::name AND table_name = p_child_tablename::name
        GROUP BY grantee
    LOOP
        IF v_parent_grant.types = v_child_grant.types AND v_parent_grant.grantee = v_child_grant.grantee THEN
            v_match := true;
        END IF;
    END LOOP;

    IF v_match = false THEN
        IF v_parent_grant.grantee = 'PUBLIC' THEN
            v_sql := 'GRANT %s ON %I.%I TO %s';
        ELSE
            v_sql := 'GRANT %s ON %I.%I TO %I';
        END IF;
        EXECUTE format(v_sql
                        , array_to_string(v_parent_grant.types, ',')
                        , p_child_schema
                        , p_child_tablename
                        , v_parent_grant.grantee);
        v_sql := NULL;
        SELECT string_agg(r, ',') INTO v_revoke FROM (SELECT unnest(v_all) AS r EXCEPT SELECT unnest(v_parent_grant.types)) x;
        IF v_revoke IS NOT NULL THEN
            IF v_parent_grant.grantee = 'PUBLIC' THEN
                v_sql := 'REVOKE %s ON %I.%I FROM %s CASCADE';
            ELSE
                v_sql := 'REVOKE %s ON %I.%I FROM %I CASCADE';
            END IF;
            EXECUTE format(v_sql
                        , v_revoke
                        , p_child_schema
                        , p_child_tablename
                        , v_parent_grant.grantee);
            v_sql := NULL;
        END IF;
    END IF;

    v_grantees := array_append(v_grantees, v_parent_grant.grantee::text);

END LOOP;

-- Revoke all privileges from roles that have none on the parent
IF v_grantees IS NOT NULL THEN
    FOR v_row_revoke IN
        SELECT role FROM (
            SELECT DISTINCT grantee::text AS role FROM @extschema@.table_privs WHERE table_schema = p_child_schema::name AND table_name = p_child_tablename::name
            EXCEPT
            SELECT unnest(v_grantees)) x
    LOOP
        IF v_row_revoke.role IS NOT NULL THEN
            IF v_row_revoke.role = 'PUBLIC' THEN
                v_sql := 'REVOKE ALL ON %I.%I FROM %s';
            ELSE
                v_sql := 'REVOKE ALL ON %I.%I FROM %I';
            END IF;
            EXECUTE format(v_sql
                        , p_child_schema
                        , p_child_tablename
                        , v_row_revoke.role);
        END IF;
    END LOOP;

END IF;

IF v_parent_owner <> v_child_owner THEN
    EXECUTE format('ALTER TABLE %I.%I OWNER TO %I'
                , p_child_schema
                , p_child_tablename
                , v_parent_owner);
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    EXECUTE format('SELECT %I.update_step(%L, %L, %L)', v_jobmon_schema, v_step_id, 'OK', 'Done');
    IF p_job_id IS NULL THEN
        EXECUTE format('SELECT %I.close_job(%L)', v_jobmon_schema, v_job_id);
    END IF;
END IF;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS ex_message = MESSAGE_TEXT,
                                ex_context = PG_EXCEPTION_CONTEXT,
                                ex_detail = PG_EXCEPTION_DETAIL,
                                ex_hint = PG_EXCEPTION_HINT;
        IF v_jobmon_schema IS NOT NULL THEN
            IF v_job_id IS NULL THEN
                EXECUTE format('SELECT %I.add_job(''PARTMAN RE-APPLYING PRIVILEGES TO ALL CHILD TABLES OF: %s'')', v_jobmon_schema, p_parent_tablename) INTO v_job_id;
                EXECUTE format('SELECT %I.add_step(%s, ''EXCEPTION before job logging started'')', v_jobmon_schema, v_job_id, p_parent_tablename) INTO v_step_id;
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


CREATE OR REPLACE VIEW @extschema@.table_privs AS
    SELECT u_grantor.rolname AS grantor,
           grantee.rolname AS grantee,
           nc.nspname AS table_schema,
           c.relname AS table_name,
           c.prtype AS privilege_type
    FROM (
            SELECT oid, relname, relnamespace, relkind, relowner, (aclexplode(coalesce(relacl, acldefault('r', relowner)))).* FROM pg_class
         ) AS c (oid, relname, relnamespace, relkind, relowner, grantor, grantee, prtype, grantable),
         pg_namespace nc,
         pg_roles u_grantor,
         (
           SELECT oid, rolname FROM pg_roles
           UNION ALL
           SELECT 0::oid, 'PUBLIC'
         ) AS grantee (oid, rolname)
    WHERE c.relnamespace = nc.oid
          AND c.relkind IN ('r', 'v', 'p')
          AND c.grantee = grantee.oid
          AND c.grantor = u_grantor.oid
          AND c.prtype IN (SELECT (aclexplode(acldefault('r'::"char", c.relowner))).privilege_type)
          AND (pg_has_role(u_grantor.oid, 'USAGE')
               OR pg_has_role(grantee.oid, 'USAGE')
               OR grantee.rolname = 'PUBLIC' );


CREATE OR REPLACE FUNCTION @extschema@.create_sub_parent(
    p_top_parent text
    , p_control text
    , p_interval text
    , p_type text DEFAULT 'range'
    , p_default_table boolean DEFAULT true
    , p_declarative_check text DEFAULT NULL
    , p_constraint_cols text[] DEFAULT NULL
    , p_premake int DEFAULT 4
    , p_start_partition text DEFAULT NULL
    , p_epoch text DEFAULT 'none'
    , p_jobmon boolean DEFAULT true
    , p_date_trunc_interval text DEFAULT NULL
    , p_control_not_null boolean DEFAULT true
    , p_time_encoder text DEFAULT NULL
    , p_time_decoder text DEFAULT NULL
)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE

BEGIN
/*
    This is an alias function for create_sub_partition() for backward compatibility
*/

RETURN @extschema@.create_sub_partition(
    p_top_parent
    , p_control
    , p_interval
    , p_type
    , p_default_table
    , p_declarative_check
    , p_constraint_cols
    , p_premake
    , p_start_partition
    , p_epoch
    , p_jobmon
    , p_date_trunc_interval
    , p_control_not_null
    , p_time_encoder
    , p_time_decoder
);

END
$$;


CREATE FUNCTION @extschema@.create_sub_partition(
    p_top_parent text
    , p_control text
    , p_interval text
    , p_type text DEFAULT 'range'
    , p_default_table boolean DEFAULT true
    , p_declarative_check text DEFAULT NULL
    , p_constraint_cols text[] DEFAULT NULL
    , p_premake int DEFAULT 4
    , p_start_partition text DEFAULT NULL
    , p_epoch text DEFAULT 'none'
    , p_jobmon boolean DEFAULT true
    , p_date_trunc_interval text DEFAULT NULL
    , p_control_not_null boolean DEFAULT true
    , p_time_encoder text DEFAULT NULL
    , p_time_decoder text DEFAULT NULL
)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE

v_child_interval         interval;
v_child_start_id         bigint;
v_child_start_time       timestamptz;
v_control                text;
v_control_parent_type    text;
v_control_sub_type       text;
v_parent_epoch           text;
v_parent_interval        text;
v_parent_schema          text;
v_parent_tablename       text;
v_part_col               text;
v_partition_id_array     bigint[];
v_partition_time_array   timestamptz[];
v_relkind                char;
v_recreate_child         boolean := false;
v_row                    record;
v_sql                    text;
v_success                boolean := false;
v_template_table         text;

BEGIN
/*
 * Create a partition set that is a subpartition of an already existing partition set.
 * Given the parent table of any current partition set, it will turn all existing children into parent tables of their own partition sets
 *      using the configuration options given as parameters to this function.
 * Uses another config table that allows for turning all future child partitions into a new parent automatically.
 *
 * IMPORTANT: Do not forget to update parameters for create_sub_parent() if they change in this function
 */

SELECT n.nspname, c.relname INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_top_parent, '.', 1)::name
AND c.relname = split_part(p_top_parent, '.', 2)::name;
    IF v_parent_tablename IS NULL THEN
        RAISE EXCEPTION 'Unable to find given parent table in system catalogs. Please create parent table first: %', p_top_parent;
    END IF;

IF NOT @extschema@.check_partition_type(p_type) THEN
    RAISE EXCEPTION '% is not a valid partitioning type', p_type;
END IF;

SELECT partition_interval, control, epoch, template_table, time_encoder
INTO v_parent_interval, v_control, v_parent_epoch, v_template_table
FROM @extschema@.part_config
WHERE parent_table = p_top_parent;
IF v_parent_interval IS NULL THEN
    RAISE EXCEPTION 'Cannot subpartition a table that is not managed by pg_partman already. Given top parent table not found in @extschema@.part_config: %', p_top_parent;
END IF;

IF (lower(p_declarative_check) <> 'yes' OR p_declarative_check IS NULL) THEN
    RAISE EXCEPTION 'Subpartitioning is a DESTRUCTIVE process unless all child tables are already themselves subpartitioned. All child tables, and therefore ALL DATA, may be destroyed since the parent table must be declared as partitioned on first creation and cannot be altered later. See docs for more info. Set p_declarative_check parameter to "yes" if you are sure this is ok.';
END IF;

SELECT general_type INTO v_control_parent_type FROM @extschema@.check_control_type(v_parent_schema, v_parent_tablename, v_control);

-- Add the given parameters to the part_config_sub table first in case create_partition_* functions are called below
-- All sub-partition parents must use the same template table, so ensure the one from the given parent is obtained and used.
INSERT INTO @extschema@.part_config_sub (
    sub_parent
    , sub_control
    , sub_time_encoder
    , sub_time_decoder
    , sub_partition_interval
    , sub_partition_type
    , sub_default_table
    , sub_constraint_cols
    , sub_premake
    , sub_automatic_maintenance
    , sub_epoch
    , sub_jobmon
    , sub_template_table
    , sub_date_trunc_interval
    , sub_control_not_null)
VALUES (
    p_top_parent
    , p_control
    , p_time_encoder
    , p_time_decoder
    , p_interval
    , p_type
    , p_default_table
    , p_constraint_cols
    , p_premake
    , 'on'
    , p_epoch
    , p_jobmon
    , v_template_table
    , p_date_trunc_interval
    , p_control_not_null);

FOR v_row IN
    -- Loop through all current children to turn them into partitioned tables
    SELECT partition_schemaname AS child_schema, partition_tablename AS child_tablename FROM @extschema@.show_partitions(p_top_parent)
LOOP

    SELECT general_type INTO v_control_sub_type FROM @extschema@.check_control_type(v_row.child_schema, v_row.child_tablename, p_control);

    SELECT c.relkind INTO v_relkind
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = v_row.child_schema
    AND c.relname = v_row.child_tablename;


    -- If both parent and sub-parent are the same partition type (time/id), ensure intereval of sub-parent is less than parent
    IF (v_control_parent_type IN ('time', 'text', 'uuid') AND v_control_sub_type = 'time') OR
       (v_control_parent_type = 'id' AND v_parent_epoch <> 'none' AND v_control_sub_type = 'id' AND p_epoch <> 'none') THEN

        v_child_interval := p_interval::interval;
        IF v_child_interval < '1 second'::interval THEN
            RAISE EXCEPTION 'Partitioning interval must be 1 second or greater';
        END IF;

        IF v_child_interval >= v_parent_interval::interval THEN
            RAISE EXCEPTION 'Sub-partition interval cannot be greater than or equal to the given parent interval';
        END IF;
        IF (v_child_interval = '1 week' AND v_parent_interval::interval > '1 week'::interval)
            OR (p_date_trunc_interval = 'week') THEN
            RAISE EXCEPTION 'Due to conflicting data boundaries between weeks and any larger interval of time, pg_partman cannot support a sub-partition interval of weekly time periods';
        END IF;

    ELSIF v_control_parent_type = 'id' AND v_control_sub_type = 'id' AND v_parent_epoch = 'none' AND p_epoch = 'none' THEN
        IF p_interval::bigint >= v_parent_interval::bigint THEN
            RAISE EXCEPTION 'Sub-partition interval cannot be greater than or equal to the given parent interval';
        END IF;
    END IF;

    IF v_relkind <> 'p' THEN
        -- Not partitioned already. Drop it and recreate as such.
        RAISE WARNING 'Child table % is not partitioned. Dropping and recreating with partitioning'
                        , v_row.child_schema||'.'||v_row.child_tablename;
        SELECT child_start_time, child_start_id INTO v_child_start_time, v_child_start_id
        FROM @extschema@.show_partition_info(v_row.child_schema||'.'||v_row.child_tablename
                                                , v_parent_interval
                                                , p_top_parent);
        EXECUTE format('DROP TABLE %I.%I', v_row.child_schema, v_row.child_tablename);
        v_recreate_child := true;

        IF v_child_start_id IS NOT NULL THEN
            v_partition_id_array[0] := v_child_start_id;
            PERFORM @extschema@.create_partition_id(p_top_parent, v_partition_id_array, p_start_partition);
        ELSIF v_child_start_time IS NOT NULL THEN
            v_partition_time_array[0] := v_child_start_time;
            PERFORM @extschema@.create_partition_time(p_top_parent, v_partition_time_array, p_start_partition);
        END IF;
    ELSE
        SELECT a.attname
        INTO v_part_col
        FROM pg_attribute a
        JOIN pg_class c ON a.attrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = v_row.child_schema::name
        AND c.relname = v_row.child_tablename::name
        AND attnum IN (SELECT unnest(partattrs) FROM pg_partitioned_table p WHERE a.attrelid = p.partrelid);

        IF p_control <> v_part_col THEN
            RAISE EXCEPTION 'Attempted to sub-partition an existing table that has the partition column (%) defined differently than the control column given (%)', v_part_col, p_control;
        ELSE -- Child table is already subpartitioned properly. Skip the rest.
            CONTINUE;
        END IF;
    END IF; -- end 'p' relkind check

IF v_recreate_child = false THEN
    -- Always call create_partition() if child table wasn't recreated above.
    -- If it was, the create_partition_*() functions called above also call create_partition() if any of the tables
    --  it creates are in the part_config_sub table. Since it was inserted there above,
    --  it should call it appropriately
        v_sql := format('SELECT @extschema@.create_partition(
                 p_parent_table := %L
                , p_control := %L
                , p_time_encoder := %L
                , p_time_decoder := %L
                , p_interval := %L
                , p_type := %L
                , p_default_table := %L
                , p_constraint_cols := %L
                , p_premake := %L
                , p_automatic_maintenance := %L
                , p_start_partition := %L
                , p_epoch := %L
                , p_template_table := %L
                , p_jobmon := %L
                , p_date_trunc_interval := %L
                , p_control_not_null := %L
                )'
            , v_row.child_schema||'.'||v_row.child_tablename
            , p_control
            , p_time_encoder
            , p_time_decoder
            , p_interval
            , p_type
            , p_default_table
            , p_constraint_cols
            , p_premake
            , 'on'
            , p_start_partition
            , p_epoch
            , v_template_table
            , p_jobmon
            , p_date_trunc_interval
            , p_control_not_null);
        RAISE DEBUG 'create_sub_partition: create parent v_sql: %', v_sql;
        EXECUTE v_sql;
    END IF; -- end recreate check

END LOOP;

v_success := true;

RETURN v_success;

END
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

    -- Same INCLUDING list is used in create_partition()
    v_sql := format('CREATE TABLE %I.%I (LIKE %I.%I  INCLUDING COMMENTS INCLUDING COMPRESSION INCLUDING CONSTRAINTS INCLUDING DEFAULTS INCLUDING GENERATED INCLUDING STATISTICS INCLUDING STORAGE) '
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
    --   create_partition, check_subpart_sameconfig, create_partition_id, create_partition_time, dump_partitioned_table_definition, and table definition
    FOR v_row IN
        SELECT
            sub_parent
            , sub_control
            , sub_time_encoder
            , sub_time_decoder
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
            , sub_control_not_null
        FROM @extschema@.part_config_sub
        WHERE sub_parent = p_parent_table
    LOOP
        IF v_jobmon_schema IS NOT NULL THEN
            v_step_id := add_step(v_job_id, 'Subpartitioning '||v_partition_name);
        END IF;
        v_sql := format('SELECT @extschema@.create_partition(
                 p_parent_table := %L
                , p_control := %L
                , p_time_encoder := %L
                , p_time_decoder := %L
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
                , p_date_trunc_interval := %L
                , p_control_not_null := %L )'
            , v_parent_schema||'.'||v_partition_name
            , v_row.sub_control
            , v_row.sub_time_encoder
            , v_row.sub_time_decoder
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
            , v_row.sub_date_trunc_interval
            , v_row.sub_control_not_null);
        RAISE DEBUG 'create_partition_id (create_partition loop): %', v_sql;
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


CREATE OR REPLACE FUNCTION @extschema@.check_subpart_sameconfig(p_parent_table text)
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
        , sub_control_not_null boolean
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
    --   create_partition, check_subpart_sameconfig, create_partition_id, create_partition_time, dump_partitioned_table_definition, and table definition
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
        , a.sub_control_not_null
    FROM @extschema@.part_config_sub a
    JOIN child_tables b on a.sub_parent = b.tablename;
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
v_time_encoder                  text;
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
v_partition_text_start          text;
v_partition_text_end            text;

BEGIN
/*
 * Function to create a child table in a time-based partition set
 */

SELECT control
    , time_encoder
    , partition_interval::interval -- this shared field also used in partition_id as bigint
    , epoch
    , jobmon
    , datetime_string
    , template_table
    , inherit_privileges
INTO v_control
    , v_time_encoder
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
    IF (v_control_type = 'id' AND v_epoch = 'none') OR v_control_type NOT IN ('text', 'id', 'uuid') OR (v_control_type IN ('text', 'uuid') AND v_time_encoder IS NULL) THEN
        RAISE EXCEPTION 'Cannot run on partition set without time based control column, an epoch flag set with an id column or time_encoder set with text column. Found control: %, epoch: %, time_encoder: %s', v_control_type, v_epoch, v_time_encoder;
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
    WHEN v_epoch = 'microseconds' THEN format('to_timestamp((%I/1000000)::float)', v_control)
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


    -- Same INCLUDING list is used in create_partition()
    v_sql := v_sql || format(' TABLE %I.%I (LIKE %I.%I INCLUDING COMMENTS INCLUDING COMPRESSION INCLUDING CONSTRAINTS INCLUDING DEFAULTS INCLUDING GENERATED INCLUDING STATISTICS INCLUDING STORAGE) '
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
        IF v_time_encoder IS NULL THEN
            EXECUTE format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I FOR VALUES FROM (%L) TO (%L)'
                , v_parent_schema
                , v_parent_tablename
                , v_parent_schema
                , v_partition_name
                , v_partition_timestamp_start
                , v_partition_timestamp_end);
        ELSE
            EXECUTE format('SELECT %s(%L)', v_time_encoder, v_partition_timestamp_start) INTO v_partition_text_start;
            EXECUTE format('SELECT %s(%L)', v_time_encoder, v_partition_timestamp_end) INTO v_partition_text_end;

            EXECUTE format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I FOR VALUES FROM (%L) TO (%L)'
                , v_parent_schema
                , v_parent_tablename
                , v_parent_schema
                , v_partition_name
                , v_partition_text_start
                , v_partition_text_end);
        END IF;

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
        ELSIF v_epoch = 'microseconds' THEN
            EXECUTE format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I FOR VALUES FROM (%L) TO (%L)'
                , v_parent_schema
                , v_parent_tablename
                , v_parent_schema
                , v_partition_name
                , EXTRACT('epoch' FROM v_partition_timestamp_start)::bigint * 1000000
                , EXTRACT('epoch' FROM v_partition_timestamp_end)::bigint * 1000000);
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
    --   create_partition, check_subpart_sameconfig, create_partition_id, create_partition_time, dump_partitioned_table_definition, and table definition
    FOR v_row IN
        SELECT
            sub_parent
            , sub_control
            , sub_time_encoder
            , sub_time_decoder
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
            , sub_control_not_null
        FROM @extschema@.part_config_sub
        WHERE sub_parent = p_parent_table
    LOOP
        IF v_jobmon_schema IS NOT NULL THEN
            v_step_id := add_step(v_job_id, format('Subpartitioning %s.%s', v_parent_schema, v_partition_name));
        END IF;
        v_sql := format('SELECT @extschema@.create_partition(
                 p_parent_table := %L
                , p_control := %L
                , p_time_encoder := %L
                , p_time_decoder := %L
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
                , p_date_trunc_interval := %L
                , p_control_not_null := %L )'
            , v_parent_schema||'.'||v_partition_name
            , v_row.sub_control
            , v_row.sub_time_encoder
            , v_row.sub_time_decoder
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
            , v_row.sub_date_trunc_interval
            , v_row.sub_control_not_null);

        RAISE DEBUG 'create_partition_time (create_partition loop): %', v_sql;
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
    v_create_partition_definition text;
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
    v_maintenance_order int;
    v_retention_keep_publication boolean;
    v_parent_schemaname text;
    v_parent_tablename text;
    v_default_exists boolean;
    v_default_tablename text;
    v_sql text;
    v_notnull boolean;
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

    SELECT schemaname, tablename
    INTO v_parent_schemaname, v_parent_tablename
    FROM pg_catalog.pg_tables
    WHERE schemaname = split_part(p_parent_table, '.', 1)::name
    AND tablename = split_part(p_parent_table, '.', 2)::name;

    -- Check to see if table has a default
    v_sql := format('SELECT c.relname
            FROM pg_catalog.pg_inherits h
            JOIN pg_catalog.pg_class c ON c.oid = h.inhrelid
            JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
            WHERE h.inhparent = ''%I.%I''::regclass
            AND pg_get_expr(relpartbound, c.oid) = ''DEFAULT'''
        , v_parent_schemaname
        , v_parent_tablename);

    EXECUTE v_sql INTO v_default_tablename;
    IF v_default_tablename IS NOT NULL THEN
        v_default_exists := true;
    ELSE
        v_default_exists := false;
    END IF;

    SELECT attnotnull INTO v_notnull
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relname = v_parent_tablename::name
    AND n.nspname = v_parent_schemaname::name
    AND a.attname = v_control::name;

    v_create_partition_definition := format(
E'SELECT @extschema@.create_partition(
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
\tp_date_trunc_interval := %L,
\tp_control_not_null := %L
);',
            v_parent_table,
            v_control,
            v_partition_interval,
            v_partition_type,
            v_epoch,
            v_premake,
            v_default_exists,
            v_automatic_maintenance,
            v_constraint_cols,
            v_template_table,
            v_jobmon,
            v_date_trunc_interval,
            v_notnull
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
        v_create_partition_definition,
        v_update_part_config_definition
    );
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
