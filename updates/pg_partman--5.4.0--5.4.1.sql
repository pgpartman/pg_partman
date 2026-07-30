-- TODO search for all instances of search_path to ensure all old code is gone
-- TODO add all SET search_path commands to each file for below functions
ALTER FUNCTION @extschema@.apply_cluster(text, text, text, text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.apply_privileges(text, text, text, text, bigint) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.autovacuum_off(text, text, text, text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.autovacuum_reset(text, text, text, text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.calculate_time_partition_info(interval, timestamptz, text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.check_control_type(text, text, text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.check_default(boolean, boolean) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.check_subpart_sameconfig(text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.check_subpartition_limits(text, text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.config_cleanup(text, boolean, boolean, boolean) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.create_parent(text, text, text, text, text, int, text, boolean, text, text[], text, boolean, text, boolean, text, text, bigint) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.create_sub_parent(text, text, text, text, boolean, text, text[], int, text, text, boolean, text, boolean, text, text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.create_sub_partition(text, text, text, text, boolean, text, text[], int, text, text, boolean, text, boolean, text, text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.dump_partitioned_table_definition(text, boolean) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.inherit_replica_identity (text, text, text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.inherit_template_properties(text, text, text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.partition_data_id(text, int, bigint, numeric, text, boolean, text, text[], boolean) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.partition_gap_fill(text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.run_maintenance( text, boolean, boolean) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.show_partition_info(text, text, text, boolean) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.show_partition_name(text, text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.show_partitions (text, text, boolean) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.stop_sub_partition(text, boolean) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.uuid7_time_encoder(timestamptz) SET search_path = @extschema@, pg_catalog, pg_temp;
-- Functions in table file
ALTER FUNCTION @extschema@.check_automatic_maintenance_value (text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.check_epoch_type (text) SET search_path = @extschema@, pg_catalog, pg_temp;
ALTER FUNCTION @extschema@.check_partition_type (text) SET search_path = @extschema@, pg_catalog, pg_temp;


CREATE OR REPLACE FUNCTION @extschema@.apply_constraints(
    p_parent_table text
    , p_child_table text DEFAULT NULL
    , p_analyze boolean DEFAULT FALSE
    , p_job_id bigint DEFAULT NULL
)
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

ex_context                      text;
ex_detail                       text;
ex_hint                         text;
ex_message                      text;
v_child_exists                  text;
v_child_tablename               text;
v_child_value                   text;
v_col                           text;
v_constraint_cols               text[];
v_constraint_name               text;
v_constraint_valid              boolean;
v_constraint_values             record;
v_control                       text;
v_control_type                  text;
v_datetime_string               text;
v_epoch                         text;
v_existing_constraint_name      text;
v_job_id                        bigint;
v_jobmon                        boolean;
v_jobmon_schema                 text;
v_last_partition                text;
v_last_partition_id             bigint;
v_last_partition_timestamp      timestamptz;
v_new_search_path               text;
v_old_search_path               text;
v_optimize_constraint           int;
v_optimize_counter              int := 0;
v_row_max_value                 record;
v_parent_schema                 text;
v_parent_table                  text;
v_parent_tablename              text;
v_partition_interval            text;
v_partition_suffix              text;
v_premake                       int;
v_sql                           text;
v_step_id                       bigint;

BEGIN
/*
 * Apply constraints managed by partman extension
 */

SELECT parent_table
    , control
    , premake
    , partition_interval
    , optimize_constraint
    , epoch
    , datetime_string
    , constraint_cols
    , jobmon
    , constraint_valid
INTO v_parent_table
    , v_control
    , v_premake
    , v_partition_interval
    , v_optimize_constraint
    , v_epoch
    , v_datetime_string
    , v_constraint_cols
    , v_jobmon
    , v_constraint_valid
FROM @extschema@.part_config
WHERE parent_table = p_parent_table
AND constraint_cols IS NOT NULL;

IF v_constraint_cols IS NULL THEN
    RAISE DEBUG 'apply_constraints: Given parent table (%) not set up for constraint management (constraint_cols is NULL)', p_parent_table;
    -- Returns silently to allow this function to be simply called by maintenance processes without having to check if config options are set.
    RETURN;
END IF;

SELECT schemaname, tablename
INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_tables
WHERE schemaname = split_part(v_parent_table, '.', 1)::name
AND tablename = split_part(v_parent_table, '.', 2)::name;

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_parent_schema, v_parent_tablename, v_control);

IF v_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        SELECT current_setting('search_path') INTO v_old_search_path;
        IF v_jobmon_schema IS NOT NULL THEN
            v_new_search_path := format('%s,%s',v_jobmon_schema, v_old_search_path);
            EXECUTE format('SET LOCAL search_path TO %s', v_new_search_path);
        END IF;
    END IF;
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    IF p_job_id IS NULL THEN
        v_job_id := add_job(format('PARTMAN CREATE CONSTRAINT: %s', v_parent_table));
    ELSE
        v_job_id = p_job_id;
    END IF;
END IF;

-- If p_child_table is null, figure out the partition that is the one right before the optimize_constraint value backwards.
IF p_child_table IS NULL THEN
    IF v_jobmon_schema IS NOT NULL THEN
        v_step_id := add_step(v_job_id, 'Applying additional constraints: Automatically determining most recent child on which to apply constraints');
    END IF;

    -- Loop through child tables starting from highest to get a value from the highest non-empty partition in the set
    -- Once a child table with a value is found, go back <optimize_constraint> + 1 children to make the constraint on that child
    FOR v_row_max_value IN
        SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(p_parent_table, 'DESC', false)
    LOOP
        IF v_child_value IS NULL THEN
            EXECUTE format('SELECT %I::text FROM %I.%I LIMIT 1'
                                , v_control
                                , v_row_max_value.partition_schemaname
                                , v_row_max_value.partition_tablename
                            ) INTO v_child_value;
        ELSE
            v_optimize_counter := v_optimize_counter + 1;
            IF v_optimize_counter > v_optimize_constraint THEN
                v_child_tablename := v_row_max_value.partition_tablename;
                EXIT;
            END IF;
        END IF;
    END LOOP;
    RAISE DEBUG 'apply_constraint: v_parent_tablename: %, v_last_partition: %, v_child_tablename: %, v_optimize_counter: %'
                , v_parent_tablename, v_last_partition, v_child_tablename, v_optimize_counter;

    IF v_jobmon_schema IS NOT NULL THEN
        PERFORM update_step(v_step_id, 'OK', format('Target child table: %s.%s', v_parent_schema, v_child_tablename));
    END IF;
ELSE
    v_child_tablename = split_part(p_child_table, '.', 2);
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    v_step_id := add_step(v_job_id, 'Applying additional constraints: Checking if target child table exists');
END IF;

SELECT tablename FROM pg_catalog.pg_tables INTO v_child_exists WHERE schemaname = v_parent_schema::name AND tablename = v_child_tablename::name;
IF v_child_exists IS NULL THEN
    IF v_jobmon_schema IS NOT NULL THEN
        PERFORM update_step(v_step_id, 'NOTICE', format('Target child table (%s) does not exist. Skipping constraint creation.', v_child_tablename));
        IF p_job_id IS NULL THEN
            PERFORM close_job(v_job_id);
        END IF;
    END IF;
    RAISE DEBUG 'Target child table (%) does not exist. Skipping constraint creation.', v_child_tablename;
    RETURN;
ELSE
    IF v_jobmon_schema IS NOT NULL THEN
        PERFORM update_step(v_step_id, 'OK', 'Done');
    END IF;
END IF;

FOREACH v_col IN ARRAY v_constraint_cols
LOOP
    SELECT con.conname
    INTO v_existing_constraint_name
    FROM pg_catalog.pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_catalog.pg_attribute a ON con.conrelid = a.attrelid
    WHERE c.relname = v_child_tablename::name
        AND n.nspname = v_parent_schema::name
        AND con.conname LIKE 'partmanconstr_%'
        AND con.contype = 'c'
        AND a.attname = v_col::name
        AND ARRAY[a.attnum] OPERATOR(pg_catalog.<@) con.conkey
        AND a.attisdropped = false;

    IF v_jobmon_schema IS NOT NULL THEN
        v_step_id := add_step(v_job_id, format('Applying additional constraints: Applying new constraint on column: %s', v_col));
    END IF;

    IF v_existing_constraint_name IS NOT NULL THEN
        IF v_jobmon_schema IS NOT NULL THEN
            PERFORM update_step(v_step_id, 'NOTICE', format('Partman managed constraint already exists on this table (%s) and column (%s). Skipping creation.', v_child_tablename, v_col));
        END IF;
        RAISE DEBUG 'Partman managed constraint already exists on this table (%) and column (%). Skipping creation.', v_child_tablename, v_col ;
        CONTINUE;
    END IF;

    -- Ensure column name gets put on end of constraint name to help avoid naming conflicts
    v_constraint_name := @extschema@.check_name_length('partmanconstr_'||v_child_tablename, p_suffix := '_'||v_col);

    EXECUTE format('SELECT min(%I)::text AS min, max(%I)::text AS max FROM %I.%I', v_col, v_col, v_parent_schema, v_child_tablename) INTO v_constraint_values;

    IF v_constraint_values IS NOT NULL THEN
        v_sql := format('ALTER TABLE %I.%I ADD CONSTRAINT %I CHECK (%I >= %L AND %I <= %L)'
                            , v_parent_schema
                            , v_child_tablename
                            , v_constraint_name
                            , v_col
                            , v_constraint_values.min
                            , v_col
                            , v_constraint_values.max);

        IF v_constraint_valid = false THEN
            v_sql := format('%s NOT VALID', v_sql);
        END IF;

        RAISE DEBUG 'Constraint creation query: %', v_sql;
        EXECUTE v_sql;

        IF v_jobmon_schema IS NOT NULL THEN
            PERFORM update_step(v_step_id, 'OK', format('New constraint created: %s', v_sql));
        END IF;
    ELSE
        RAISE DEBUG 'Given column (%) contains all NULLs. No constraint created', v_col;
        IF v_jobmon_schema IS NOT NULL THEN
            PERFORM update_step(v_step_id, 'NOTICE', format('Given column (%s) contains all NULLs. No constraint created', v_col));
        END IF;
    END IF;

END LOOP;

IF p_analyze THEN
    IF v_jobmon_schema IS NOT NULL THEN
        v_step_id := add_step(v_job_id, format('Applying additional constraints: Running analyze on partition set: %s', v_parent_table));
    END IF;
    RAISE DEBUG 'Running analyze on partition set: %', v_parent_table;
    EXECUTE format('ANALYZE %I.%I', v_parent_schema, v_parent_tablename);

    IF v_jobmon_schema IS NOT NULL THEN
        PERFORM update_step(v_step_id, 'OK', 'Done');
    END IF;
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    PERFORM close_job(v_job_id);
END IF;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS ex_message = MESSAGE_TEXT,
                                ex_context = PG_EXCEPTION_CONTEXT,
                                ex_detail = PG_EXCEPTION_DETAIL,
                                ex_hint = PG_EXCEPTION_HINT;
        IF v_jobmon_schema IS NOT NULL THEN
            IF v_job_id IS NULL THEN
                EXECUTE format('SELECT %I.add_job(''PARTMAN CREATE CONSTRAINT: %s'')', v_jobmon_schema, p_parent_table) INTO v_job_id;
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


CREATE OR REPLACE FUNCTION @extschema@.create_partition(
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
    SET search_path = @extschema@, pg_catalog, pg_temp
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

IF p_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        SELECT current_setting('search_path') INTO v_old_search_path;
        IF v_jobmon_schema IS NOT NULL THEN
            v_new_search_path := format('%s,%s',v_jobmon_schema, v_old_search_path);
            EXECUTE format('SET LOCAL search_path TO %s', v_new_search_path);
        END IF;
    END IF;
END IF;

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


CREATE OR REPLACE FUNCTION @extschema@.create_partition_id(
    p_parent_table text
    , p_partition_ids bigint[]
    , p_start_partition text DEFAULT NULL
)
    RETURNS boolean
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
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

IF v_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        SELECT current_setting('search_path') INTO v_old_search_path;
        IF v_jobmon_schema IS NOT NULL THEN
            v_new_search_path := format('%s,%s',v_jobmon_schema, v_old_search_path);
            EXECUTE format('SET LOCAL search_path TO %s', v_new_search_path);
        END IF;
    END IF;
END IF;

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
    SET search_path = @extschema@, pg_catalog, pg_temp
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

IF v_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        SELECT current_setting('search_path') INTO v_old_search_path;
        IF v_jobmon_schema IS NOT NULL THEN
            v_new_search_path := format('%s,%s',v_jobmon_schema, v_old_search_path);
            EXECUTE format('SET LOCAL search_path TO %s', v_new_search_path);
        END IF;
    END IF;
END IF;

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


CREATE OR REPLACE FUNCTION @extschema@.drop_constraints(p_parent_table text, p_child_table text, p_debug boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

ex_context                      text;
ex_detail                       text;
ex_hint                         text;
ex_message                      text;
v_child_schemaname              text;
v_child_tablename               text;
v_col                           text;
v_constraint_cols               text[];
v_existing_constraint_name      text;
v_exists                        boolean := FALSE;
v_job_id                        bigint;
v_jobmon                        boolean;
v_jobmon_schema                 text;
v_new_search_path               text;
v_old_search_path               text;
v_sql                           text;
v_step_id                       bigint;

BEGIN
/*
 * Drop constraints managed by pg_partman
 */

SELECT constraint_cols
    , jobmon
INTO v_constraint_cols
    , v_jobmon
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;

IF v_constraint_cols IS NULL THEN
    RAISE EXCEPTION 'Given parent table (%) not set up for constraint management (constraint_cols is NULL)', p_parent_table;
END IF;

IF v_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        SELECT current_setting('search_path') INTO v_old_search_path;
        IF v_jobmon_schema IS NOT NULL THEN
            v_new_search_path := format('%s,%s',v_jobmon_schema, v_old_search_path);
            EXECUTE format('SET LOCAL search_path TO %s', v_new_search_path);
        END IF;
    END IF;
END IF;

SELECT schemaname, tablename INTO v_child_schemaname, v_child_tablename
FROM pg_catalog.pg_tables
WHERE schemaname = split_part(p_child_table, '.', 1)::name
AND tablename = split_part(p_child_table, '.', 2)::name;
IF v_child_tablename IS NULL THEN
    RAISE EXCEPTION 'Unable to find given child table in system catalogs: %', p_child_table;
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    v_job_id := add_job(format('PARTMAN DROP CONSTRAINT: %s', p_parent_table));
    v_step_id := add_step(v_job_id, 'Entering constraint drop loop');
    PERFORM update_step(v_step_id, 'OK', 'Done');
END IF;


FOREACH v_col IN ARRAY v_constraint_cols
LOOP
    SELECT con.conname
    INTO v_existing_constraint_name
    FROM pg_catalog.pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_catalog.pg_attribute a ON con.conrelid = a.attrelid
    WHERE c.relname = v_child_tablename
        AND n.nspname = v_child_schemaname
        AND con.conname LIKE 'partmanconstr_%'
        AND con.contype = 'c'
        AND a.attname = v_col
        AND ARRAY[a.attnum] OPERATOR(pg_catalog.<@) con.conkey
        AND a.attisdropped = false;

    IF v_existing_constraint_name IS NOT NULL THEN
        v_exists := TRUE;
        IF v_jobmon_schema IS NOT NULL THEN
            v_step_id := add_step(v_job_id, format('Dropping constraint on column: %s', v_col));
        END IF;
        v_sql := format('ALTER TABLE %I.%I DROP CONSTRAINT %I', v_child_schemaname, v_child_tablename, v_existing_constraint_name);
        IF p_debug THEN
            RAISE NOTICE 'Constraint drop query: %', v_sql;
        END IF;
        EXECUTE v_sql;
        IF v_jobmon_schema IS NOT NULL THEN
            PERFORM update_step(v_step_id, 'OK', format('Drop constraint query: %s', v_sql));
        END IF;
    END IF;

END LOOP;

IF v_jobmon_schema IS NOT NULL AND v_exists IS FALSE THEN
    v_step_id := add_step(v_job_id, format('No constraints found to drop on child table: %s', p_child_table));
    PERFORM update_step(v_step_id, 'OK', 'Done');
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    PERFORM close_job(v_job_id);
END IF;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS ex_message = MESSAGE_TEXT,
                                ex_context = PG_EXCEPTION_CONTEXT,
                                ex_detail = PG_EXCEPTION_DETAIL,
                                ex_hint = PG_EXCEPTION_HINT;
        IF v_jobmon_schema IS NOT NULL THEN
            IF v_job_id IS NULL THEN
                EXECUTE format('SELECT %I.add_job(''PARTMAN DROP CONSTRAINT: %s'')', v_jobmon_schema, p_parent_table) INTO v_job_id;
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


CREATE OR REPLACE FUNCTION @extschema@.drop_partition_id(
    p_parent_table text
    , p_retention bigint DEFAULT NULL
    , p_keep_table boolean DEFAULT NULL
    , p_keep_index boolean DEFAULT NULL
    , p_retention_schema text DEFAULT NULL
)
    RETURNS int
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
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

IF v_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        SELECT current_setting('search_path') INTO v_old_search_path;
        IF v_jobmon_schema IS NOT NULL THEN
            v_new_search_path := format('%s,%s',v_jobmon_schema, v_old_search_path);
            EXECUTE format('SET LOCAL search_path TO %s', v_new_search_path);
        END IF;
    END IF;
END IF;

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
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

ex_context                          text;
ex_detail                           text;
ex_hint                             text;
ex_message                          text;
v_adv_lock                          boolean;
v_control                           text;
v_control_type                      text;
v_time_encoder                      text;
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
        , time_encoder
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
        , v_time_encoder
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
    IF (v_control_type = 'id' AND v_epoch = 'none') OR v_control_type <> 'id' OR (v_control_type IN ('text', 'uuid') AND v_time_encoder IS NULL) THEN
        RAISE EXCEPTION 'Cannot run on partition set without time based control column, an epoch flag set with an id column or time_encoder set with text column. Found control: %, epoch: %', v_control_type, v_epoch;
    END IF;
END IF;

IF v_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        SELECT current_setting('search_path') INTO v_old_search_path;
        IF v_jobmon_schema IS NOT NULL THEN
            v_new_search_path := format('%s,%s',v_jobmon_schema, v_old_search_path);
            EXECUTE format('SET LOCAL search_path TO %s', v_new_search_path);
        END IF;
    END IF;
END IF;

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
    -- Add one interval since partition lower boundary is the start of the constraint period
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


CREATE OR REPLACE FUNCTION @extschema@.reapply_privileges(p_parent_table text) RETURNS void
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

ex_context          text;
ex_detail           text;
ex_hint             text;
ex_message          text;
v_job_id            bigint;
v_jobmon            boolean;
v_jobmon_schema     text;
v_new_search_path   text;
v_old_search_path   text;
v_parent_schema     text;
v_parent_tablename  text;
v_row               record;
v_step_id           bigint;

BEGIN

/*
 * Function to re-apply ownership & privileges on all child tables in a partition set using parent table as reference
 */

SELECT jobmon INTO v_jobmon FROM @extschema@.part_config WHERE parent_table = p_parent_table;
IF v_jobmon IS NULL THEN
    RAISE EXCEPTION 'Given table is not managed by this extension: %', p_parent_table;
END IF;

IF v_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        SELECT current_setting('search_path') INTO v_old_search_path;
        IF v_jobmon_schema IS NOT NULL THEN
            v_new_search_path := format('%s,%s',v_jobmon_schema, v_old_search_path);
            EXECUTE format('SET LOCAL search_path TO %s', v_new_search_path);
        END IF;
    END IF;
END IF;

SELECT schemaname, tablename INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_tables
WHERE schemaname = split_part(p_parent_table, '.', 1)::name
AND tablename = split_part(p_parent_table, '.', 2)::name;
IF v_parent_tablename IS NULL THEN
    RAISE EXCEPTION 'Given parent table does not exist: %', p_parent_table;
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    v_job_id := add_job(format('PARTMAN RE-APPLYING PRIVILEGES TO ALL CHILD TABLES OF: %s', p_parent_table));
END IF;

FOR v_row IN
    SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(p_parent_table, 'ASC', p_include_default := true)
LOOP
    PERFORM @extschema@.apply_privileges(v_parent_schema, v_parent_tablename, v_row.partition_schemaname, v_row.partition_tablename, v_job_id);
END LOOP;

IF v_jobmon_schema IS NOT NULL THEN
    PERFORM close_job(v_job_id);
END IF;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS ex_message = MESSAGE_TEXT,
                                ex_context = PG_EXCEPTION_CONTEXT,
                                ex_detail = PG_EXCEPTION_DETAIL,
                                ex_hint = PG_EXCEPTION_HINT;
        IF v_jobmon_schema IS NOT NULL THEN
            IF v_job_id IS NULL THEN
                EXECUTE format('SELECT %I.add_job(''PARTMAN RE-APPLYING PRIVILEGES TO ALL CHILD TABLES OF: %s'')', v_jobmon_schema, p_parent_table) INTO v_job_id;
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


CREATE OR REPLACE FUNCTION @extschema@.run_maintenance(
    p_parent_table text DEFAULT NULL
    -- If these defaults change reflect them in `run_maintenance_proc`!
    , p_analyze boolean DEFAULT false
    , p_jobmon boolean DEFAULT true
)
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

ex_context                      text;
ex_detail                       text;
ex_hint                         text;
ex_message                      text;
v_adv_lock                      boolean;
v_analyze                       boolean := FALSE;
v_check_subpart                 int;
v_child_timestamp               timestamptz;
v_control_type                  text;
v_time_encoder                  text;
v_time_decoder                  text;
v_create_count                  int := 0;
v_current_partition_id          bigint;
v_current_partition_timestamp   timestamptz;
v_default_tablename             text;
v_default_version               text;
v_drop_count                    int := 0;
v_exact_control_type            text;
v_installed_version             text;
v_is_default                    text;
v_job_id                        bigint;
v_jobmon_schema                 text;
v_last_partition                text;
v_last_partition_created        boolean;
v_last_partition_id             bigint;
v_last_partition_timestamp      timestamptz;
v_library_version               text;
v_max_id                        bigint;
v_max_id_default                bigint;
v_max_time_default              timestamptz;
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

IF p_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        SELECT current_setting('search_path') INTO v_old_search_path;
        IF v_jobmon_schema IS NOT NULL THEN
            v_new_search_path := format('%s,%s',v_jobmon_schema, v_old_search_path);
            EXECUTE format('SET LOCAL search_path TO %s', v_new_search_path);
        END IF;
    END IF;
END IF;

IF current_setting('server_version_num')::int >= 180000 THEN
    SELECT extversion INTO v_installed_version FROM pg_catalog.pg_extension WHERE extname = 'pg_partman';
    SELECT version INTO v_library_version FROM pg_catalog.pg_get_loaded_modules() WHERE module_name = 'pg_partman';

    IF replace(v_installed_version, '.', '')::int < replace(v_library_version, '.', '')::int THEN
        RAISE EXCEPTION 'The installed version of pg_partman (%) is less than the shared library version file that has been loaded (%). Please ensure the expected version of pg_partman is installed to the system, update the extension if needed and restart the PostgreSQL instance.', v_installed_version, v_library_version;
    END IF;
END IF;

-- Try and catch the same situation of a new library file existing on disk but the extension version not being updated properly in the database. Not as reliable as new feature in PG18, but better than nothing. Only do a warning since this is less definitely a problem than a known library mismatch.
SELECT default_version, installed_version INTO v_default_version, v_installed_version FROM pg_available_extensions WHERE name = 'pg_partman' AND default_version != installed_version;
IF v_installed_version IS NOT NULL THEN
    RAISE WARNING 'pg_partman version % is installed in the database but version % is the default available. Please ensure the expected version of pg_partman is installed to the system, update the extension in all relevant databases and restart the PostgreSQL instance if a new shared library module is available. See release notes for further details.', v_installed_version, v_default_version;
END IF;

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
                , date_trunc_interval
                , async_partitioning_in_progress
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

    IF v_row.async_partitioning_in_progress IS NOT NULL THEN
        RAISE WARNING 'Async partitioning in progress for partition set: %. Maintenance is being skipped for this partition set while this is in progress and will resume when it is complete during the next maintenance run. If this is not expected, please check the value of "async_partitioning_in_progress" in the "part_config" table and investigate for any incomplete asynchronous partitioning job attempts for this partition set.', v_row.parent_table;
        CONTINUE;
    END IF;

    -- When sub-partitioning, retention may drop tables that were already put into the query loop values.
    -- Check if they still exist in part_config before continuing
    v_parent_exists := NULL;
    SELECT parent_table, time_encoder, time_decoder INTO v_parent_exists, v_time_encoder, v_time_decoder FROM @extschema@.part_config WHERE parent_table = v_row.parent_table;
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
        WHEN v_row.epoch = 'microseconds' THEN format('to_timestamp((%I/1000000)::float)', v_row.control)
        WHEN v_row.epoch = 'nanoseconds' THEN format('to_timestamp((%I/1000000000)::float)', v_row.control)
        ELSE format('%I', v_row.control)
    END;
    RAISE DEBUG 'run_maint: v_partition_expression: %', v_partition_expression;

    SELECT partition_tablename INTO v_last_partition FROM @extschema@.show_partitions(v_row.parent_table, 'DESC') LIMIT 1;
    RAISE DEBUG 'run_maint: parent_table: %, v_last_partition: %', v_row.parent_table, v_last_partition;

    IF v_control_type = 'time' OR (v_control_type = 'id' AND v_row.epoch <> 'none') OR (v_control_type IN ('text', 'uuid')) THEN

        IF v_row.sub_partition_set_full THEN
            UPDATE @extschema@.part_config SET maintenance_last_run = clock_timestamp() WHERE parent_table = v_row.parent_table;
            CONTINUE;
        END IF;

        SELECT child_start_time INTO v_last_partition_timestamp
            FROM @extschema@.show_partition_info(v_parent_schema||'.'||v_last_partition, v_row.partition_interval, v_row.parent_table);

        -- Do not create child tables if they would be dropped by retention anyway. Edge case where maintenance was missed for
        --  an extended period of time
        IF v_row.retention IS NOT NULL THEN
            v_last_partition_timestamp := greatest(v_last_partition_timestamp, CURRENT_TIMESTAMP - v_row.retention::interval);
            -- Need to properly truncate the interval and account for custom date truncation
            SELECT base_timestamp
            INTO v_last_partition_timestamp
            FROM @extschema@.calculate_time_partition_info(v_row.partition_interval::interval, v_last_partition_timestamp, v_row.date_trunc_interval);
        END IF;

        -- Must be reset to null otherwise if the next partition set in the loop is empty, the previous partition set's value could be used
        v_current_partition_timestamp := NULL;

        -- Loop through child tables starting from highest to get a timestamp from the highest non-empty partition in the set
        -- Avoids doing a scan on entire partition set and/or getting any values accidentally in default.
        FOR v_row_max_time IN
            SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(v_row.parent_table, 'DESC', false)
        LOOP
            IF v_control_type = 'time' OR (v_control_type = 'id' AND v_row.epoch <> 'none') THEN
                EXECUTE format('SELECT %s::text FROM %I.%I LIMIT 1'
                                    , v_partition_expression
                                    , v_row_max_time.partition_schemaname
                                    , v_row_max_time.partition_tablename
                                ) INTO v_child_timestamp;
            ELSIF v_control_type IN ('text', 'uuid') THEN
                EXECUTE format('SELECT %s(%s::text) FROM %I.%I LIMIT 1'
                                    , v_time_decoder
                                    , v_partition_expression
                                    , v_row_max_time.partition_schemaname
                                    , v_row_max_time.partition_tablename
                                ) INTO v_child_timestamp;
            END IF;

            IF v_row.infinite_time_partitions AND v_child_timestamp < CURRENT_TIMESTAMP THEN
                -- No new data has been inserted relative to "now", but keep making child tables anyway
                v_current_partition_timestamp = CURRENT_TIMESTAMP;
                -- Nothing else to do in this case so just end early
                EXIT;
            END IF;
            IF v_child_timestamp IS NOT NULL THEN
                SELECT suffix_timestamp INTO v_current_partition_timestamp FROM @extschema@.show_partition_name(v_row.parent_table, v_child_timestamp::text);
                EXIT;
            END IF;
        END LOOP;
        IF v_row.infinite_time_partitions AND v_child_timestamp IS NULL THEN
            -- If partition set is completely empty, still keep making child tables anyway
            -- Has to be separate check outside above loop since "future" tables are likely going to be empty, hence ignored in that loop
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

            -- Still need to run retention if needed. Note similar call below for non-empty sets. Keep in sync.
            IF v_row.retention IS NOT NULL THEN
                v_drop_count := v_drop_count + @extschema@.drop_partition_time(v_row.parent_table);
            END IF;

            -- Nothing else to do
            UPDATE @extschema@.part_config SET maintenance_last_run = clock_timestamp() WHERE parent_table = v_row.parent_table;
            CONTINUE;
        END IF;
        RAISE DEBUG 'run_maint: v_child_timestamp: %, v_current_partition_timestamp: %, v_max_time_default: %', v_child_timestamp, v_current_partition_timestamp, v_max_time_default;
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

        -- Run retention if needed. Note similar call above when partition set is empty. Keep in sync.
        IF v_row.retention IS NOT NULL THEN
            v_drop_count := v_drop_count + @extschema@.drop_partition_time(v_row.parent_table);
        END IF;

    ELSIF v_control_type = 'id' THEN

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
            -- Partition set is completely empty.

            -- Still need to run retention if needed. Note similar call below for non-empty sets. Keep in sync.
            IF v_row.retention IS NOT NULL THEN
                v_drop_count := v_drop_count + @extschema@.drop_partition_id(v_row.parent_table);
            END IF;

            -- Nothing else to do
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

        -- Run retention if needed. Note similar call above when partition set is empty. Keep in sync.
        IF v_row.retention IS NOT NULL THEN
            v_drop_count := v_drop_count + @extschema@.drop_partition_id(v_row.parent_table);
        END IF;

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


CREATE OR REPLACE FUNCTION @extschema@.undo_partition(
    p_parent_table text
    , p_target_table text
    , p_loop_count int DEFAULT 1
    , p_batch_interval text DEFAULT NULL
    , p_keep_table boolean DEFAULT true
    , p_lock_wait numeric DEFAULT 0
    , p_ignored_columns text[] DEFAULT NULL
    , p_drop_cascade boolean DEFAULT false
    , OUT partitions_undone int
    , OUT rows_undone bigint
)
    RETURNS record
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

ex_context                      text;
ex_detail                       text;
ex_hint                         text;
ex_message                      text;
v_adv_lock                      boolean;
v_batch_interval_id             bigint;
v_batch_interval_time           interval;
v_batch_loop_count              int := 0;
v_child_loop_total              bigint := 0;
v_child_table                   text;
v_column_list                   text;
v_control                       text;
v_control_type                  text;
v_time_encoder                  text;
v_time_decoder                  text;
v_child_min_id                  bigint;
v_child_min_time                timestamptz;
v_epoch                         text;
v_function_name                 text;
v_jobmon                        boolean;
v_jobmon_schema                 text;
v_job_id                        bigint;
v_inner_loop_count              int;
v_lock_iter                     int := 1;
v_lock_obtained                 boolean := FALSE;
v_new_search_path               text;
v_old_search_path               text;
v_parent_schema                 text;
v_parent_tablename              text;
v_partition_expression          text;
v_partition_interval            text;
v_row                           record;
v_rowcount                      bigint;
v_sql                           text;
v_step_id                       bigint;
v_sub_count                     int;
v_target_schema                 text;
v_target_tablename              text;
v_template_schema               text;
v_template_siblings             int;
v_template_table                text;
v_template_tablename            text;
v_total                         bigint := 0;
v_trig_name                     text;
v_undo_count                    int := 0;

BEGIN
/*
 * Moves data to new, target table since data cannot be moved elsewhere in the same partition set.
 * Leaves old parent table as is and does not change name of new table.
 */

v_adv_lock := pg_try_advisory_xact_lock(hashtext('pg_partman undo_partition'));
IF v_adv_lock = 'false' THEN
    RAISE NOTICE 'undo_partition already running.';
    partitions_undone = -1;
    RETURN;
END IF;

IF p_parent_table = p_target_table THEN
    RAISE EXCEPTION 'Target table cannot be the same as the parent table';
END IF;

SELECT partition_interval::text
    , control
    , time_encoder
    , time_decoder
    , jobmon
    , epoch
    , template_table
INTO v_partition_interval
    , v_control
    , v_time_encoder
    , v_time_decoder
    , v_jobmon
    , v_epoch
    , v_template_table
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;

IF v_control IS NULL THEN
    RAISE EXCEPTION 'No configuration found for pg_partman for given parent table: %', p_parent_table;
END IF;

IF p_target_table IS NULL THEN
    RAISE EXCEPTION 'The p_target_table option must be set when undoing a partitioned table';
END IF;

SELECT n.nspname, c.relname
INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_parent_table, '.', 1)::name
AND c.relname = split_part(p_parent_table, '.', 2)::name;

IF v_parent_tablename IS NULL THEN
    RAISE EXCEPTION 'Given parent table not found in system catalogs: %', p_parent_table;
END IF;

SELECT general_type INTO v_control_type FROM @extschema@.check_control_type(v_parent_schema, v_parent_tablename, v_control);
IF v_control_type IN ('time', 'text', 'uuid') OR (v_control_type = 'id' AND v_epoch <> 'none') THEN
    IF p_batch_interval IS NULL THEN
        v_batch_interval_time := v_partition_interval::interval;
    ELSE
        v_batch_interval_time := p_batch_interval::interval;
    END IF;
ELSIF v_control_type = 'id' THEN
    IF p_batch_interval IS NULL THEN
        v_batch_interval_id := v_partition_interval::bigint;
    ELSE
        v_batch_interval_id := p_batch_interval::bigint;
    END IF;
ELSE
    RAISE EXCEPTION 'Data type of control column in given partition set must be either date/time or integer.';
END IF;

IF v_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon'::name AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        SELECT current_setting('search_path') INTO v_old_search_path;
        IF v_jobmon_schema IS NOT NULL THEN
            v_new_search_path := format('%s,%s',v_jobmon_schema, v_old_search_path);
            EXECUTE format('SET LOCAL search_path TO %s', v_new_search_path);
        END IF;
    END IF;
END IF;

-- Check if any child tables are themselves partitioned or part of an inheritance tree. Prevent undo at this level if so.
-- Need to lock child tables at all levels before multi-level undo can be performed safely.
FOR v_row IN
    SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(p_parent_table)
LOOP
    SELECT count(*) INTO v_sub_count
    FROM pg_catalog.pg_inherits i
    JOIN pg_catalog.pg_class c ON i.inhparent = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE c.relname = v_row.partition_tablename::name
    AND n.nspname = v_row.partition_schemaname::name;
    IF v_sub_count > 0 THEN
        RAISE EXCEPTION 'Child table for this parent has child table(s) itself (%). Run undo partitioning on this table to ensure all data is properly moved to target table', v_row.partition_schemaname||'.'||v_row.partition_tablename;
    END IF;
END LOOP;

SELECT n.nspname, c.relname
INTO v_target_schema, v_target_tablename
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_target_table, '.', 1)::name
AND c.relname = split_part(p_target_table, '.', 2)::name;

IF v_target_tablename IS NULL THEN
    RAISE EXCEPTION 'Given target table not found in system catalogs: %', p_target_table;
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    v_job_id := add_job(format('PARTMAN UNDO PARTITIONING: %s', p_parent_table));
    v_step_id := add_step(v_job_id, format('Undoing partitioning for table %s', p_parent_table));
END IF;

v_partition_expression := CASE
    WHEN v_epoch = 'seconds' THEN format('to_timestamp(%I)', v_control)
    WHEN v_epoch = 'milliseconds' THEN format('to_timestamp((%I/1000)::float)', v_control)
    WHEN v_epoch = 'microseconds' THEN format('to_timestamp((%I/1000000)::float)', v_control)
    WHEN v_epoch = 'nanoseconds' THEN format('to_timestamp((%I/1000000000)::float)', v_control)
    ELSE format('%I', v_control)
END;

-- Stops new time partitions from being made as well as stopping child tables from being dropped if they were configured with a retention period.
UPDATE @extschema@.part_config SET undo_in_progress = true WHERE parent_table = p_parent_table;


IF v_jobmon_schema IS NOT NULL THEN
    IF (v_trig_name IS NOT NULL OR v_function_name IS NOT NULL) THEN
        PERFORM update_step(v_step_id, 'OK', 'Stopped partition creation process. Removed trigger & trigger function');
    ELSE
        PERFORM update_step(v_step_id, 'OK', 'Stopped partition creation process.');
    END IF;
END IF;

-- Generate column list to use in SELECT/INSERT statements below. Allows for exclusion of GENERATED (or any other desired) columns.
SELECT string_agg(quote_ident(attname), ',')
INTO v_column_list
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = v_target_schema
AND c.relname = v_target_tablename
AND a.attnum > 0
AND a.attisdropped = false
AND attname <> ALL(COALESCE(p_ignored_columns, ARRAY[]::text[]));

<<outer_child_loop>>
LOOP
    -- Get ordered list of child table in set. Store in variable one at a time per loop until none are left or batch count is reached.
    -- This easily allows it to loop over same child table until empty or move onto next child table after it's dropped
    -- Include the default table to ensure all data there is removed as well
    SELECT partition_tablename INTO v_child_table FROM @extschema@.show_partitions(p_parent_table, 'ASC', p_include_default := TRUE) LIMIT 1;

    EXIT outer_child_loop WHEN v_child_table IS NULL;

    IF v_jobmon_schema IS NOT NULL THEN
        v_step_id := add_step(v_job_id, format('Removing child partition: %s.%s', v_parent_schema, v_child_table));
    END IF;

    IF v_control_type = 'time' OR (v_control_type = 'id' AND v_epoch <> 'none') THEN
        EXECUTE format('SELECT min(%s) FROM %I.%I', v_partition_expression, v_parent_schema, v_child_table) INTO v_child_min_time;
    ELSIF (v_control_type IN ('text', 'uuid')) THEN
        --- This can pass NULL to decoder function
        EXECUTE format('SELECT %s((SELECT min(%s::text) FROM %I.%I))', v_time_decoder, v_partition_expression, v_parent_schema, v_child_table) INTO v_child_min_time;
    ELSIF v_control_type = 'id' THEN
        EXECUTE format('SELECT min(%s) FROM %I.%I', v_partition_expression, v_parent_schema, v_child_table) INTO v_child_min_id;
    END IF;

    IF v_child_min_time IS NULL AND v_child_min_id IS NULL THEN
        -- No rows left in this child table. Remove from partition set.

        -- lockwait timeout for table drop
        IF p_lock_wait > 0  THEN
            v_lock_iter := 0;
            WHILE v_lock_iter <= 5 LOOP
                v_lock_iter := v_lock_iter + 1;
                BEGIN
                    EXECUTE format('LOCK TABLE ONLY %I.%I IN ACCESS EXCLUSIVE MODE NOWAIT', v_parent_schema, v_child_table);
                    v_lock_obtained := TRUE;
                EXCEPTION
                    WHEN lock_not_available THEN
                        PERFORM pg_sleep( p_lock_wait / 5.0 );
                        CONTINUE;
                END;
                EXIT WHEN v_lock_obtained;
            END LOOP;
            IF NOT v_lock_obtained THEN
                RAISE NOTICE 'Unable to obtain lock on child table for removal from partition set';
                partitions_undone = -1;
                RETURN;
            END IF;
        END IF; -- END p_lock_wait IF
        v_lock_obtained := FALSE; -- reset for reuse later

        v_sql := format('ALTER TABLE %I.%I DETACH PARTITION %I.%I'
                        , v_parent_schema
                        , v_parent_tablename
                        , v_parent_schema
                        , v_child_table);
        EXECUTE v_sql;

        IF p_keep_table = false THEN
            v_sql := 'DROP TABLE %I.%I';
            IF p_drop_cascade THEN
                v_sql := v_sql || ' CASCADE';
            END IF;
            EXECUTE format(v_sql, v_parent_schema, v_child_table);
            IF v_jobmon_schema IS NOT NULL THEN
                PERFORM update_step(v_step_id, 'OK', format('Child table DROPPED. Moved %s rows to target table', v_child_loop_total));
            END IF;
        ELSE
            IF v_jobmon_schema IS NOT NULL THEN
                PERFORM update_step(v_step_id, 'OK', format('Child table DETACHED/UNINHERITED from parent, not DROPPED. Moved %s rows to target table', v_child_loop_total));
            END IF;
        END IF;

        v_undo_count := v_undo_count + 1;
        EXIT outer_child_loop WHEN v_batch_loop_count >= p_loop_count; -- Exit outer FOR loop if p_loop_count is reached
        CONTINUE outer_child_loop; -- skip data moving steps below
    END IF;
    v_inner_loop_count := 1;
    v_child_loop_total := 0;
    <<inner_child_loop>>
    LOOP
        IF v_control_type IN ('time', 'text', 'uuid') OR (v_control_type = 'id' AND v_epoch <> 'none') THEN
            -- do some locking with timeout, if required
            IF p_lock_wait > 0  THEN
                v_lock_iter := 0;
                WHILE v_lock_iter <= 5 LOOP
                    v_lock_iter := v_lock_iter + 1;
                    BEGIN
                        IF v_control_type = 'time' OR (v_control_type = 'id' AND v_epoch <> 'none') THEN
                            EXECUTE format('SELECT * FROM %I.%I WHERE %I <= %L FOR UPDATE NOWAIT'
                                , v_parent_schema
                                , v_child_table
                                , v_control
                                , v_child_min_time + (v_batch_interval_time * v_inner_loop_count));
                        ELSIF (v_control_type IN ('text', 'uuid')) THEN
                            EXECUTE format('SELECT * FROM %I.%I WHERE %I <= %s(%L) FOR UPDATE NOWAIT'
                                , v_parent_schema
                                , v_child_table
                                , v_control
                                , v_time_encoder
                                , v_child_min_time + (v_batch_interval_time * v_inner_loop_count));
                        END IF;
                       v_lock_obtained := TRUE;
                    EXCEPTION
                        WHEN lock_not_available THEN
                            PERFORM pg_sleep( p_lock_wait / 5.0 );
                            CONTINUE;
                    END;
                    EXIT WHEN v_lock_obtained;
                END LOOP;
                IF NOT v_lock_obtained THEN
                    RAISE NOTICE 'Unable to obtain lock on batch of rows to move';
                    partitions_undone = -1;
                    RETURN;
                END IF;
            END IF;

            -- Get everything from the current child minimum up to the multiples of the given interval
            IF v_control_type = 'time' OR (v_control_type = 'id' AND v_epoch <> 'none') THEN
                EXECUTE format('WITH move_data AS (
                                        DELETE FROM %I.%I WHERE %s <= %L RETURNING %s )
                                    INSERT INTO %I.%I (%5$s) SELECT %5$s FROM move_data'
                    , v_parent_schema
                    , v_child_table
                    , v_partition_expression
                    , v_child_min_time + (v_batch_interval_time * v_inner_loop_count)
                    , v_column_list
                    , v_target_schema
                    , v_target_tablename);
            ELSIF (v_control_type IN ('text', 'uuid')) THEN
                EXECUTE format('WITH move_data AS (
                                        DELETE FROM %I.%I WHERE %s <= %s(%L) RETURNING %s )
                                    INSERT INTO %I.%I (%6$s) SELECT %6$s FROM move_data'
                    , v_parent_schema
                    , v_child_table
                    , v_partition_expression
                    , v_time_encoder
                    , v_child_min_time + (v_batch_interval_time * v_inner_loop_count)
                    , v_column_list
                    , v_target_schema
                    , v_target_tablename);
            END IF;

            GET DIAGNOSTICS v_rowcount = ROW_COUNT;
            v_total := v_total + v_rowcount;
            v_child_loop_total := v_child_loop_total + v_rowcount;
            IF v_jobmon_schema IS NOT NULL THEN
                PERFORM update_step(v_step_id, 'OK', format('Moved %s rows to target table.', v_child_loop_total));
            END IF;
            EXIT inner_child_loop WHEN v_rowcount = 0; -- exit before loop incr if table is empty
            v_inner_loop_count := v_inner_loop_count + 1;
            v_batch_loop_count := v_batch_loop_count + 1;

            -- Check again if table is empty and go to outer loop again to drop it if so

            IF v_control_type = 'time' OR (v_control_type = 'id' AND v_epoch <> 'none') THEN
                EXECUTE format('SELECT min(%s) FROM %I.%I', v_partition_expression, v_parent_schema, v_child_table) INTO v_child_min_time;
            ELSIF (v_control_type IN ('text', 'uuid')) THEN
                EXECUTE format('SELECT %s((SELECT min(%s::text) FROM %I.%I))', v_time_decoder, v_partition_expression, v_parent_schema, v_child_table) INTO v_child_min_time;
            END IF;

            CONTINUE outer_child_loop WHEN v_child_min_time IS NULL;

        ELSIF v_control_type = 'id' THEN

            IF p_lock_wait > 0  THEN
                v_lock_iter := 0;
                WHILE v_lock_iter <= 5 LOOP
                    v_lock_iter := v_lock_iter + 1;
                    BEGIN
                        EXECUTE format('SELECT * FROM %I.%I WHERE %I <= %L FOR UPDATE NOWAIT'
                            , v_parent_schema
                            , v_child_table
                            , v_control
                            , v_child_min_id + (v_batch_interval_id * v_inner_loop_count));
                       v_lock_obtained := TRUE;
                    EXCEPTION
                        WHEN lock_not_available THEN
                            PERFORM pg_sleep( p_lock_wait / 5.0 );
                            CONTINUE;
                    END;
                    EXIT WHEN v_lock_obtained;
                END LOOP;
                IF NOT v_lock_obtained THEN
                   RAISE NOTICE 'Unable to obtain lock on batch of rows to move';
                   partitions_undone = -1;
                   RETURN;
                END IF;
            END IF;

            -- Get everything from the current child minimum up to the multiples of the given interval
            EXECUTE format('WITH move_data AS (
                                    DELETE FROM %I.%I WHERE %s <= %L RETURNING %s)
                                  INSERT INTO %I.%I (%5$s) SELECT %5$s FROM move_data'
                , v_parent_schema
                , v_child_table
                , v_partition_expression
                , v_child_min_id + (v_batch_interval_id * v_inner_loop_count)
                , v_column_list
                , v_target_schema
                , v_target_tablename);
            GET DIAGNOSTICS v_rowcount = ROW_COUNT;
            v_total := v_total + v_rowcount;
            v_child_loop_total := v_child_loop_total + v_rowcount;
            IF v_jobmon_schema IS NOT NULL THEN
                PERFORM update_step(v_step_id, 'OK', format('Moved %s rows to target table.', v_child_loop_total));
            END IF;
            EXIT inner_child_loop WHEN v_rowcount = 0; -- exit before loop incr if table is empty
            v_inner_loop_count := v_inner_loop_count + 1;
            v_batch_loop_count := v_batch_loop_count + 1;

            -- Check again if table is empty and go to outer loop again to drop it if so
            EXECUTE format('SELECT min(%s) FROM %I.%I', v_partition_expression, v_parent_schema, v_child_table) INTO v_child_min_id;
            CONTINUE outer_child_loop WHEN v_child_min_id IS NULL;

        END IF; -- end v_control_type check

        EXIT outer_child_loop WHEN v_batch_loop_count >= p_loop_count; -- Exit outer FOR loop if p_loop_count is reached

    END LOOP inner_child_loop;
END LOOP outer_child_loop;

SELECT partition_tablename INTO v_child_table FROM @extschema@.show_partitions(p_parent_table, 'ASC', TRUE) LIMIT 1;

IF v_child_table IS NULL THEN
    DELETE FROM @extschema@.part_config WHERE parent_table = p_parent_table;

    -- Check if any other config entries still have this template table and don't remove if so
    -- Allows other sibling/parent tables to still keep using in case entire partition set isn't being undone
    SELECT count(*) INTO v_template_siblings FROM @extschema@.part_config WHERE template_table = v_template_table;

    SELECT n.nspname, c.relname
    INTO v_template_schema, v_template_tablename
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = split_part(v_template_table, '.', 1)::name
    AND c.relname = split_part(v_template_table, '.', 2)::name;

    IF v_template_siblings = 0 AND v_template_tablename IS NOT NULL THEN
        EXECUTE format('DROP TABLE IF EXISTS %I.%I', v_template_schema, v_template_tablename);
    END IF;

    IF v_jobmon_schema IS NOT NULL THEN
        v_step_id := add_step(v_job_id, 'Removing config from pg_partman');
        PERFORM update_step(v_step_id, 'OK', 'Done');
    END IF;
END IF;

RAISE NOTICE 'Moved % row(s) to the target table. Removed % partitions.', v_total, v_undo_count;
IF v_jobmon_schema IS NOT NULL THEN
    v_step_id := add_step(v_job_id, 'Final stats');
    PERFORM update_step(v_step_id, 'OK', format('Moved %s row(s) to the target table. Removed %s partitions.', v_total, v_undo_count));
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    PERFORM close_job(v_job_id);
END IF;

partitions_undone := v_undo_count;
rows_undone := v_total;

EXCEPTION
    WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS ex_message = MESSAGE_TEXT,
                                ex_context = PG_EXCEPTION_CONTEXT,
                                ex_detail = PG_EXCEPTION_DETAIL,
                                ex_hint = PG_EXCEPTION_HINT;
        IF v_jobmon_schema IS NOT NULL THEN
            IF v_job_id IS NULL THEN
                EXECUTE format('SELECT %I.add_job(''PARTMAN UNDO PARTITIONING: %s'')', v_jobmon_schema, p_parent_table) INTO v_job_id;
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


CREATE OR REPLACE PROCEDURE @extschema@.partition_data_async (
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


CREATE OR REPLACE PROCEDURE @extschema@.partition_data_proc (
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

v_adv_lock := pg_catalog.pg_try_advisory_lock(hashtext('pg_partman partition_data_proc'), hashtext(p_parent_table));
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
    AND c.relname = pg_catalog.split_part(p_source_table, '.', 2)::name;
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

v_sql := pg_catalog.format('SELECT %s.partition_data_%s (p_parent_table := %L
                                                , p_lock_wait := %L
                                                , p_order := %L
                                                , p_analyze := false'
        , '@extschema@', v_control_type, p_parent_table, p_lock_wait, p_order, p_ignore_infinity);
IF p_interval IS NOT NULL THEN
    v_sql := v_sql || pg_catalog.format(', p_batch_interval := %L', p_interval);
END IF;
IF p_source_table IS NOT NULL THEN
    v_sql := v_sql || pg_catalog.format(', p_source_table := %L', p_source_table);
END IF;
IF p_ignored_columns IS NOT NULL THEN
    v_sql := v_sql || pg_catalog.format(', p_ignored_columns := %L', p_ignored_columns);
END IF;
IF v_control_type = 'time' THEN
    v_sql := v_sql || pg_catalog.format(', p_ignore_infinity := %L', p_ignore_infinity);
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
    PERFORM pg_catalog.pg_sleep(p_wait);
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

PERFORM pg_catalog.pg_advisory_unlock(hashtext('pg_partman partition_data_proc'), hashtext(p_parent_table));
END;
$$;


CREATE OR REPLACE PROCEDURE @extschema@.reapply_constraints_proc(
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

v_adv_lock := pg_catalog.pg_try_advisory_lock(hashtext('pg_partman reapply_constraints'));
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
WHERE n.nspname = pg_catalog.split_part(p_parent_table, '.', 1)::name
AND c.relname = pg_catalog.split_part(p_parent_table, '.', 2)::name;
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

v_sql := pg_catalog.format('SELECT partition_schemaname, partition_tablename FROM @extschema@.show_partitions(%L, %L)', p_parent_table, 'ASC');

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
    PERFORM pg_catalog.pg_sleep(p_wait);
END LOOP;

IF p_analyze THEN
    IF p_dryrun THEN
        RAISE NOTICE 'ANALYZE %.%', v_parent_schema, v_parent_tablename;
    ELSE
        EXECUTE pg_catalog.format('ANALYZE %I.%I', v_parent_schema, v_parent_tablename);
    END IF;
END IF;

PERFORM pg_catalog.pg_advisory_unlock(hashtext('pg_partman reapply_constraints'));
END
$$;


CREATE OR REPLACE PROCEDURE @extschema@.run_analyze(p_skip_locked boolean DEFAULT false, p_quiet boolean DEFAULT false, p_parent_table text DEFAULT NULL)
    LANGUAGE plpgsql
    AS $$
DECLARE

v_adv_lock              boolean;
v_parent_schema         text;
v_parent_tablename      text;
v_row                   record;
v_sql                   text;

BEGIN

v_adv_lock := pg_catalog.pg_try_advisory_lock(hashtext('pg_partman run_analyze'));
IF v_adv_lock = false THEN
    RAISE NOTICE 'Partman analyze already running or another session has not released its advisory lock.';
    RETURN;
END IF;

FOR v_row IN SELECT parent_table FROM @extschema@.part_config
LOOP

    IF p_parent_table IS NOT NULL THEN
        IF p_parent_table != v_row.parent_table THEN
            CONTINUE;
        END IF;
    END IF;

    SELECT n.nspname, c.relname
    INTO v_parent_schema, v_parent_tablename
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = pg_catalog.split_part(v_row.parent_table, '.', 1)::name
    AND c.relname = pg_catalog.split_part(v_row.parent_table, '.', 2)::name;

    v_sql := 'ANALYZE ';
    IF p_skip_locked THEN
        v_sql := v_sql || 'SKIP LOCKED ';
    END IF;
    v_sql := pg_catalog.format('%s %I.%I', v_sql, v_parent_schema, v_parent_tablename);

    IF p_quiet = 'false' THEN
        RAISE NOTICE 'Analyzed partitioned table: %.%', v_parent_schema, v_parent_tablename;
    END IF;
    EXECUTE v_sql;
    COMMIT;

END LOOP;

PERFORM pg_catalog.pg_advisory_unlock(hashtext('pg_partman run_analyze'));
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

v_adv_lock := pg_catalog.pg_try_advisory_lock(hashtext('pg_partman run_maintenance_proc'));
IF v_adv_lock = false THEN
    RAISE NOTICE 'Advisory lock notice (pg_partman run_maintenance_proc): Partman maintenance procedure already running or another session has not released its advisory lock.';
    RETURN;
END IF;

IF pg_catalog.pg_is_in_recovery() THEN
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
    v_sql := pg_catalog.format('SELECT %s.run_maintenance(%L, p_jobmon := %L',
        '@extschema@', v_parent_table, p_jobmon);

    IF p_analyze IS NOT NULL THEN
        v_sql := v_sql || pg_catalog.format(', p_analyze := %L', p_analyze);
    END IF;

    v_sql := v_sql || ')';

    RAISE DEBUG 'v_sql run_maintenance_proc: %', v_sql;

    EXECUTE v_sql;
    COMMIT;

    PERFORM pg_catalog.pg_sleep(p_wait);

END LOOP;

PERFORM pg_catalog.pg_advisory_unlock(hashtext('pg_partman run_maintenance_proc'));
END
$$;


CREATE OR REPLACE PROCEDURE @extschema@.undo_partition_proc(
    p_parent_table text
    , p_target_table text DEFAULT NULL
    , p_loop_count int DEFAULT NULL
    , p_interval text DEFAULT NULL
    , p_keep_table boolean DEFAULT true
    , p_lock_wait int DEFAULT 0
    , p_lock_wait_tries int DEFAULT 10
    , p_wait int DEFAULT 1
    , p_ignored_columns text[] DEFAULT NULL
    , p_drop_cascade boolean DEFAULT false
    , p_quiet boolean DEFAULT false
)
    LANGUAGE plpgsql
    AS $$
DECLARE

v_adv_lock                  boolean;
v_is_autovac_off            boolean := false;
v_lockwait_count            int := 0;
v_loop_count               int := 0;
v_parent_schema             text;
v_parent_tablename          text;
v_partition_type            text;
v_partitions_undone         int;
v_partitions_undone_total   int := 0;
v_rows_undone               bigint;
v_target_tablename          text;
v_sql                       text;
v_total                     bigint := 0;

BEGIN

v_adv_lock := pg_catalog.pg_try_advisory_xact_lock(hashtext('pg_partman undo_partition_proc'), hashtext(p_parent_table));
IF v_adv_lock = 'false' THEN
    RAISE NOTICE 'Partman undo_partition_proc already running for given parent table: %.', p_parent_table;
    RETURN;
END IF;

SELECT partition_type
INTO v_partition_type
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;
IF NOT FOUND THEN
    RAISE EXCEPTION 'ERROR: No entry in part_config found for given table: %', p_parent_table;
END IF;

IF p_target_table IS NULL THEN
    RAISE EXCEPTION 'The p_target_table option must be set when undoing a partitioned table';
END IF;

SELECT n.nspname, c.relname INTO v_parent_schema, v_parent_tablename
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = split_part(p_parent_table, '.', 1)::name
AND c.relname = split_part(p_parent_table, '.', 2)::name;
    IF v_parent_tablename IS NULL THEN
        RAISE EXCEPTION 'Unable to find given parent table in system catalogs. Ensure it is schema qualified: %', p_parent_table;
    END IF;

IF p_target_table IS NOT NULL THEN
    SELECT c.relname INTO v_target_tablename
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = split_part(p_target_table, '.', 1)::name
    AND c.relname = split_part(p_target_table, '.', 2)::name;
        IF v_target_tablename IS NULL THEN
            RAISE EXCEPTION 'Unable to find given target table in system catalogs. Ensure it is schema qualified: %', p_target_table;
        END IF;
END IF;

/*
-- Currently no way to catch exception and reset autovac settings back to normal. Until I can do that, leaving this feature out for now
-- Leaving the functions to turn off/reset in to let people do that manually if desired
IF p_autovacuum_on = false THEN         -- Add this parameter back to definition when this is working
    -- Turn off autovac for parent, source table if set, and all child tables
    v_is_autovac_off := @extschema@.autovacuum_off(v_parent_schema, v_parent_tablename, v_source_schema, v_source_tablename);
    COMMIT;
END IF;
*/

v_sql := pg_catalog.format('SELECT partitions_undone, rows_undone FROM %s.undo_partition (%L, p_keep_table := %L, p_lock_wait := %L'
        , '@extschema@'
        , p_parent_table
        , p_keep_table
        , p_lock_wait);
IF p_interval IS NOT NULL THEN
    v_sql := v_sql || pg_catalog.format(', p_batch_interval := %L', p_interval);
END IF;
IF p_target_table IS NOT NULL THEN
    v_sql := v_sql || pg_catalog.format(', p_target_table := %L', p_target_table);
END IF;
IF p_ignored_columns IS NOT NULL THEN
    v_sql := v_sql || pg_catalog.format(', p_ignored_columns := %L', p_ignored_columns);
END IF;
IF p_drop_cascade IS NOT NULL THEN
    v_sql := v_sql || pg_catalog.format(', p_drop_cascade := %L', p_drop_cascade);
END IF;
v_sql := v_sql || ')';
RAISE DEBUG 'partition_data sql: %', v_sql;

LOOP
    EXECUTE v_sql INTO v_partitions_undone, v_rows_undone;
    -- If lock wait timeout, do not increment the counter
    IF v_rows_undone != -1 THEN
        v_loop_count := v_loop_count + 1;
        v_partitions_undone_total := v_partitions_undone_total + v_partitions_undone;
        v_total := v_total + v_rows_undone;
        v_lockwait_count := 0;
    ELSE
        v_lockwait_count := v_lockwait_count + 1;
        IF v_lockwait_count > p_lock_wait_tries THEN
            RAISE EXCEPTION 'Quitting due to inability to get lock on next batch of rows to be moved';
        END IF;
    END IF;
    IF p_quiet = false THEN
        IF v_rows_undone > 0 THEN
            RAISE NOTICE 'Batch: %, Partitions undone this batch: %, Rows undone this batch: %', v_loop_count, v_partitions_undone, v_rows_undone;
        ELSIF v_rows_undone = -1 THEN
            RAISE NOTICE 'Unable to obtain row locks for data to be moved. Trying again...';
        END IF;
    END IF;
    COMMIT;

    -- If no rows left or given loop argument limit is reached
    IF v_rows_undone = 0 OR (p_loop_count > 0 AND v_loop_count >= p_loop_count) THEN
        EXIT;
    END IF;

    -- undo_partition functions will remove config entry once last child is dropped
    -- Added here to handle edge-case
    SELECT partition_type
    INTO v_partition_type
    FROM @extschema@.part_config
    WHERE parent_table = p_parent_table;
    IF NOT FOUND THEN
        EXIT;
    END IF;

    PERFORM pg_catalog.pg_sleep(p_wait);

    RAISE DEBUG 'v_partitions_undone: %, v_rows_undone: %, v_loop_count: %, v_total: %, v_lockwait_count: %, p_wait: %', v_partitions_undone, p_wait, v_rows_undone, v_loop_count, v_total, v_lockwait_count;
END LOOP;

/*
IF v_is_autovac_off = true THEN
    -- Reset autovac back to default if it was turned off by this procedure
    PERFORM @extschema@.autovacuum_reset(v_parent_schema, v_parent_tablename, v_source_schema, v_source_tablename);
    COMMIT;
END IF;
*/

IF p_quiet = false THEN
    RAISE NOTICE 'Total partitions undone: %, Total rows moved: %', v_partitions_undone_total, v_total;
END IF;
RAISE NOTICE 'Ensure to VACUUM ANALYZE the old parent & target table after undo has finished';

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

SELECT general_type, exact_type INTO v_control_type, v_control_exact_type FROM partman.check_control_type(v_parent_schemaname, v_parent_tablename, v_control);
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
