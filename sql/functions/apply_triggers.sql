/*
 * Apply triggers that exist on the given parent to the given child table
 */
CREATE OR REPLACE FUNCTION partman.apply_triggers(p_parent_table text, p_child_table text DEFAULT NULL, p_debug boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE

v_job_id            bigint;
v_jobmon            text;
v_jobmon_schema     text;
v_old_search_path   text;
v_row               record;
v_schemaname        text;
v_sql               text;
v_step_id           bigint;
v_tablename         text;

BEGIN

SELECT jobmon INTO v_jobmon FROM partman.part_config WHERE parent_table = p_parent_table;

IF v_jobmon THEN
    SELECT nspname INTO v_jobmon_schema FROM pg_catalog.pg_namespace n, pg_catalog.pg_extension e WHERE e.extname = 'pg_jobmon' AND e.extnamespace = n.oid;
    IF v_jobmon_schema IS NOT NULL THEN
        SELECT current_setting('search_path') INTO v_old_search_path;
        EXECUTE 'SELECT set_config(''search_path'',''@extschema@,'||v_jobmon_schema||''',''false'')';
    END IF;
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    v_job_id := add_job('PARTMAN APPLYING TRIGGERS: '||p_parent_table);
END IF;

IF v_jobmon_schema IS NOT NULL THEN
    v_step_id := add_step(v_job_id, 'Checking if target child table exists');
END IF;

SELECT schemaname, tablename INTO v_schemaname, v_tablename 
FROM pg_catalog.pg_tables 
WHERE schemaname||'.'||tablename = p_child_table;

IF v_tablename IS NULL THEN
    IF v_jobmon_schema IS NOT NULL THEN
        PERFORM update_step(v_step_id, 'CRITICAL', 'Target child table ('||v_child_table||') does not exist.');
        PERFORM fail_job(v_job_id);
        EXECUTE 'SELECT set_config(''search_path'','''||v_old_search_path||''',''false'')';
    END IF;
    RAISE EXCEPTION 'Target child table (%.%) does not exist.', v_schemaname, v_tablename;
    RETURN;
ELSE
    IF v_jobmon_schema IS NOT NULL THEN
        PERFORM update_step(v_step_id, 'OK', 'Done');
    END IF;
END IF;

FOR v_row IN 
    select distinct trg.oid as trigger_oid, 
    	   trg.tgname as trigger_name,
	       s.nspname AS schema_name,
	       tbl.relname as table_name
	from pg_trigger trg,
	     pg_class tbl,
	     pg_namespace s,
	     pg_proc p
	where trg.tgrelid = tbl.oid
		and s.oid = tbl.relnamespace
		and s.nspname || '.' || tbl.relname = p_parent_table
LOOP
    /* Get the trigger definition */
	v_sql := pg_get_triggerdef(v_row.trigger_oid);
    /* Replace parent table name with child table name */
	v_sql := replace(v_sql, p_parent_table, p_child_table);
	/* Replace trigger name with one defined automatically */
	v_sql := replace(v_sql, v_row.trigger_name, @extschema@.check_name_length('partmantrg_'||v_tablename));		

    IF v_jobmon_schema IS NOT NULL THEN
        v_step_id := add_step(v_job_id, 'Creating Trigger: '||v_sql);
    END IF;

    EXECUTE v_sql;

    IF v_jobmon_schema IS NOT NULL THEN
        PERFORM update_step(v_step_id, 'OK', 'Trigger created');
    END IF;

END LOOP;

IF v_jobmon_schema IS NOT NULL THEN
    PERFORM close_job(v_job_id);
    EXECUTE 'SELECT set_config(''search_path'','''||v_old_search_path||''',''false'')';
END IF;

EXCEPTION
    WHEN OTHERS THEN
        IF v_jobmon_schema IS NOT NULL THEN
            IF v_job_id IS NULL THEN
                EXECUTE 'SELECT '||v_jobmon_schema||'.add_job(''PARTMAN APPLYING TRIGGERS: '||p_parent_table||''')' INTO v_job_id;
                EXECUTE 'SELECT '||v_jobmon_schema||'.add_step('||v_job_id||', ''EXCEPTION before job logging started'')' INTO v_step_id;
            ELSIF v_step_id IS NULL THEN
                EXECUTE 'SELECT '||v_jobmon_schema||'.add_step('||v_job_id||', ''EXCEPTION before first step logged'')' INTO v_step_id;
            END IF;
            EXECUTE 'SELECT '||v_jobmon_schema||'.update_step('||v_step_id||', ''CRITICAL'', ''ERROR: '||coalesce(SQLERRM,'unknown')||''')';
            EXECUTE 'SELECT '||v_jobmon_schema||'.fail_job('||v_job_id||')';
        END IF;
        RAISE EXCEPTION '%', SQLERRM;
END
$$;
