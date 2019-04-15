CREATE FUNCTION @extschema@.create_partition_default(p_parent_table text, p_job_id bigint DEFAULT NULL)
    RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE

v_default_partition     text;
v_parent_schema         text;
v_parent_table          text;
v_parent_tablename      text;
v_parent_tablespace     text;
v_partition_type        text;
v_unlogged              text;
v_sql                   text;

BEGIN

SELECT n.nspname, c.relname, t.spcname, c.relpersistence
INTO v_parent_schema, v_parent_tablename, v_parent_tablespace, v_unlogged
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
LEFT OUTER JOIN pg_catalog.pg_tablespace t ON c.reltablespace = t.oid
WHERE n.nspname = split_part(p_parent_table, '.', 1)::name
AND c.relname = split_part(p_parent_table, '.', 2)::name;

IF v_parent_tablename IS NULL THEN
    RAISE EXCEPTION 'Unable to find given parent table in system catalogs. Please create parent table first: %', p_parent_table;
END IF;

SELECT parent_table
    , partition_type
INTO v_parent_table
    , v_partition_type
FROM @extschema@.part_config
WHERE parent_table = p_parent_table;

IF v_partition_type = 'native' AND current_setting('server_version_num')::int >= 110000 THEN
    -- Add default partition to native sets in PG11+

    v_default_partition := @extschema@.check_name_length(v_parent_tablename, '_default', FALSE);
    v_sql := 'CREATE';
    IF v_unlogged = 'u' THEN
        v_sql := v_sql ||' UNLOGGED';
    END IF;
    -- Same INCLUDING list is used in create_partition_*()
    v_sql := v_sql || format(' TABLE %I.%I (LIKE %I.%I INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING STORAGE INCLUDING COMMENTS)'
        , v_parent_schema, v_default_partition, v_parent_schema, v_parent_tablename);
    EXECUTE v_sql;
    v_sql := format('ALTER TABLE %I.%I ATTACH PARTITION %I.%I DEFAULT'
        , v_parent_schema, v_parent_tablename, v_parent_schema, v_default_partition);
    EXECUTE v_sql;

    IF v_parent_tablespace IS NOT NULL THEN
        EXECUTE format('ALTER TABLE %I.%I SET TABLESPACE %I', v_parent_schema, v_default_partition, v_parent_tablespace);
    END IF;

    -- NOTE: Privileges currently not automatically inherited for native
    PERFORM @extschema@.apply_privileges(v_parent_schema, v_parent_tablename, v_parent_schema, v_default_partition, p_job_id);
END IF;
END
$$;
