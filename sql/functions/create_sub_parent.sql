CREATE FUNCTION @extschema@.create_sub_parent(
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
)
    RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE

v_child_interval        interval;
v_child_start_id        bigint;
v_child_start_time      timestamptz;
v_control               text;
v_control_parent_type   text;
v_control_sub_type      text;
v_parent_epoch          text;
v_parent_interval       text;
v_parent_schema         text;
v_parent_tablename      text;
v_part_col              text;
v_partition_id_array    bigint[];
v_partition_time_array  timestamptz[];
v_relkind               char;
v_recreate_child        boolean := false;
v_row                   record;
v_sql                   text;
v_success               boolean := false;
v_template_table        text;

BEGIN
/*
 * Create a partition set that is a subpartition of an already existing partition set.
 * Given the parent table of any current partition set, it will turn all existing children into parent tables of their own partition sets
 *      using the configuration options given as parameters to this function.
 * Uses another config table that allows for turning all future child partitions into a new parent automatically.
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

SELECT partition_interval, control, epoch, template_table
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
    , sub_partition_interval
    , sub_partition_type
    , sub_default_table
    , sub_constraint_cols
    , sub_premake
    , sub_automatic_maintenance
    , sub_epoch
    , sub_jobmon
    , sub_template_table
    , sub_date_trunc_interval)
VALUES (
    p_top_parent
    , p_control
    , p_interval
    , p_type
    , p_default_table
    , p_constraint_cols
    , p_premake
    , 'on'
    , p_epoch
    , p_jobmon
    , v_template_table
    , p_date_trunc_interval);

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
    IF (v_control_parent_type = 'time' AND v_control_sub_type = 'time') OR
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
    -- Always call create_parent() if child table wasn't recreated above.
    -- If it was, the create_partition_*() functions called above also call create_parent if any of the tables
    --  it creates are in the part_config_sub table. Since it was inserted there above,
    --  it should call it appropriately
        v_sql := format('SELECT @extschema@.create_parent(
                 p_parent_table := %L
                , p_control := %L
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
                , p_date_trunc_interval := %L)'
            , v_row.child_schema||'.'||v_row.child_tablename
            , p_control
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
            , p_date_trunc_interval);
        RAISE DEBUG 'create_sub_parent: create parent v_sql: %', v_sql;
        EXECUTE v_sql;
    END IF; -- end recreate check

END LOOP;

v_success := true;

RETURN v_success;

END
$$;
