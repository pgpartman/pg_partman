CREATE FUNCTION @extschema@.inherit_replica_identity (p_parent_schemaname text, p_parent_tablename text, p_child_tablename text) RETURNS void
    LANGUAGE plpgsql
    SET search_path = @extschema@, pg_catalog, pg_temp
    AS $$
DECLARE

v_child_partition_index         text;
v_child_partition_oid           oid;
v_parent_oid                    oid;
v_parent_replident              char;
v_parent_replident_oid          oid;
v_replident_string              text;
v_sql                           text;

BEGIN

/*
* Set the given child table's replica identity to the same as the parent
 NOTE: Replication identity not automatically inherited as of PG16 (revisit in future versions).
 ANOTHER NOTE: Replica identity with USING INDEX only works with indexes that actually exist on the parent,
    not indexes that are inherited from the template.  Since the replica identity could be defined on both
    the template and the parent at the same time , there's no way to tell which one is the "right" one.
    Using the parent table's replica identity index at least ensures the index inheritance relationship.
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

    SELECT c.oid
    INTO v_parent_replident_oid
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_index i ON i.indexrelid = c.oid
    WHERE i.indrelid = v_parent_oid
    AND indisreplident;

    SELECT c.oid
    INTO v_child_partition_oid
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = p_parent_schemaname
    AND c.relname = p_child_tablename;

    SELECT partition_index_name.relname
    INTO v_child_partition_index
    FROM pg_index parent_index
    INNER JOIN pg_catalog.pg_inherits index_inheritance ON (index_inheritance.inhparent=parent_index.indexrelid) -- parent index inheritance
    INNER JOIN pg_catalog.pg_index partition_index ON (index_inheritance.inhrelid=partition_index.indexrelid) -- connection between parent index and child index
    INNER JOIN pg_catalog.pg_class partition_index_name ON (partition_index.indexrelid=partition_index_name.oid) -- get child index name
    INNER JOIN pg_catalog.pg_class partition_table ON (partition_table.oid=partition_index.indrelid) -- connection between child table and child index
    WHERE partition_table.oid=v_child_partition_oid -- child partition table
    AND parent_index.indexrelid=v_parent_replident_oid; -- parent partition index

END IF;

RAISE DEBUG 'inherit_replica_ident: v_parent_oid: %, v_parent_replident: %, v_parent_replident_oid: %, v_child_partition_oid: %, v_child_partition_index: %', v_parent_oid, v_parent_replident,  v_parent_replident_oid, v_child_partition_oid, v_child_partition_index;

IF v_parent_replident != 'd' THEN
    CASE v_parent_replident
        WHEN 'f' THEN v_replident_string := 'FULL';
        WHEN 'i' THEN v_replident_string := format('USING INDEX %I', v_child_partition_index);
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
