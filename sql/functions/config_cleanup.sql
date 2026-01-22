CREATE FUNCTION @extschema@.config_cleanup(
    p_parent_table text
    , p_config_table boolean DEFAULT true
    , p_config_sub_table boolean DEFAULT true
    , p_template_table boolean DEFAULT true
)
    RETURNS void
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
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
