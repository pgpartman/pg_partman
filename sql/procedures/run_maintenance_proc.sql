CREATE PROCEDURE @extschema@.run_maintenance_proc(
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

v_adv_lock := pg_try_advisory_lock(hashtext('pg_partman run_maintenance'));
IF v_adv_lock = false THEN
    RAISE NOTICE 'Partman maintenance already running or another session has not released its advisory lock.';
    RETURN;
END IF;

FOR v_parent_table IN
    SELECT parent_table
    FROM @extschema@.part_config
    WHERE undo_in_progress = false
    AND automatic_maintenance = 'on'
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

PERFORM pg_advisory_unlock(hashtext('pg_partman run_maintenance'));
END
$$;
