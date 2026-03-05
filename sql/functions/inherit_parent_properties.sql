CREATE FUNCTION @extschema@.inherit_parent_properties(p_parent_schema text, p_parent_tablename text, p_child_tablename text, p_child_schema text DEFAULT NULL) RETURNS void
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

v_sql   text;

BEGIN
/*
 * Function to inherit properties like per column statistics target that exist on a given parent to the given child table
 */

p_child_schema := coalesce(p_child_schema, p_parent_schema);

SELECT string_agg(
    format('ALTER COLUMN %I SET STATISTICS %s', a.attname, a.attstattarget::integer),
    ', '
)
INTO v_sql
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE a.attnum > 0
AND NOT a.attisdropped
AND c.relname = p_parent_tablename::name
AND n.nspname= p_parent_schema::name
AND a.attstattarget >= 0;

IF v_sql IS NOT NULL THEN
    v_sql := format('ALTER TABLE %I.%I '
                , p_child_schema
                , p_child_tablename) || v_sql;
    RAISE DEBUG 'inherit_parent_properties: Set column statistics target: %', v_sql;
    EXECUTE v_sql;
END IF;

END
$$;
