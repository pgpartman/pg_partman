CREATE PROCEDURE @extschema@.reapply_constraints_proc(p_parent_table text, p_drop_constraints boolean DEFAULT false, p_apply_constraints boolean DEFAULT false, p_wait int DEFAULT 0, p_dryrun boolean DEFAULT false)
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

    IF v_row.partition_tablename = v_child_stop THEN
        RAISE DEBUG 'reapply_constraint: Reached stop at %.%', v_row.partition_schemaname, v_row.partition_tablename;
        EXIT; -- stop creating constraints after optimize target is reached
    END IF;
    COMMIT;
    PERFORM pg_sleep(p_wait);
END LOOP;

EXECUTE format('ANALYZE %I.%I', v_parent_schema, v_parent_tablename);

PERFORM pg_advisory_unlock(hashtext('pg_partman reapply_constraints'));
END
$$;
