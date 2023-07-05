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
p_parent_table          text;

BEGIN

v_adv_lock := pg_try_advisory_lock(hashtext('pg_partman run_maintenance'));
IF v_adv_lock = false THEN
    RAISE NOTICE 'Partman maintenance already running or another session has not released its advisory lock.';
    RETURN;
END IF;

FOR p_parent_table IN
    SELECT parent_table
    FROM @extschema@.part_config
    WHERE undo_in_progress = false
    AND automatic_maintenance = 'on'
LOOP
/*
 * Run maintenance with a commit between each partition set
 * TODO - Once PG11 is more mainstream, see about more full conversion of run_maintenance function as well as turning
 *        create_partition* functions into procedures to commit after every child table is made. May need to wait
 *        for more PROCEDURE features as well (return values, search_path, etc).
 *      - Also see about swapping names so this is the main object to call for maintenance instead of a function.
 */
    RAISE DEBUG 'run_maintenance_proc for table: %', p_parent_table;
    PERFORM @extschema@.run_maintenance(p_parent_table, p_jobmon => p_jobmon, p_analyze => p_analyze);
    COMMIT;

    PERFORM pg_sleep(p_wait);

END LOOP;

PERFORM pg_advisory_unlock(hashtext('pg_partman run_maintenance'));
END
$$;

