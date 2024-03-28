CREATE FUNCTION @extschema@.inherit_replica_identity (p_parent_schemaname text, p_parent_tablename text, p_child_tablename text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE

v_parent_oid                    oid;
v_parent_replident              char;
v_parent_replident_index        name;
v_replident_string              text;
v_sql                           text;

BEGIN

/*
* Set the given child table's replica idenitity to the same as the parent
 NOTE: Replication identity not automatically inherited as of PG16 (revisit in future versions)
*/

SELECT c.oid
    , c.relreplident
INTO v_parent_oid
    , v_parent_replident
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = p_parent_schemaname
AND c.relname = p_parent_tablename;

IF v_parent_replident = 'i' THEN
    SELECT c.relname
    INTO v_parent_replident_index
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_index i ON i.indexrelid = c.oid
    WHERE i.indrelid = v_parent_oid
    AND indisreplident;
END IF;

RAISE DEBUG 'inherit_replica_ident: v_parent_oid: %, v_parent_replident: %,  v_parent_replident_index: %', v_parent_oid, v_parent_replident,  v_parent_replident_index;

IF v_parent_replident != 'd' THEN
    CASE v_parent_replident
        WHEN 'f' THEN v_replident_string := 'FULL';
        WHEN 'i' THEN v_replident_string := format('USING INDEX %I', v_parent_replident_index);
        WHEN 'n' THEN v_replident_string := 'NOTHING';
    ELSE
        RAISE EXCEPTION 'inherit_replica_identity: Unknown replication identity encountered (%). Please report as a bug on pg_partman''s github', v_parent_replident;
    END CASE;
    v_sql := format('ALTER TABLE %I.%I REPLICA IDENTITY %s'
                    , p_parent_schemaname
                    , p_child_tablename
                    , v_replident_string);
    RAISE DEBUG 'inherit_replica_identity: replident v_sql: %', v_sql;
    EXECUTE v_sql;
END IF;

END
$$;
