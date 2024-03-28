CREATE TABLE @extschema@.part_config (
    parent_table text NOT NULL
    , control text NOT NULL
    , partition_interval text NOT NULL
    , partition_type text NOT NULL
    , premake int NOT NULL DEFAULT 4
    , automatic_maintenance text NOT NULL DEFAULT 'on'
    , template_table text
    , retention text
    , retention_schema text
    , retention_keep_index boolean NOT NULL DEFAULT true
    , retention_keep_table boolean NOT NULL DEFAULT true
    , epoch text NOT NULL DEFAULT 'none'
    , constraint_cols text[]
    , optimize_constraint int NOT NULL DEFAULT 30
    , infinite_time_partitions boolean NOT NULL DEFAULT false
    , datetime_string text
    , jobmon boolean NOT NULL DEFAULT true
    , sub_partition_set_full boolean NOT NULL DEFAULT false
    , undo_in_progress boolean NOT NULL DEFAULT false
    , inherit_privileges boolean DEFAULT false
    , constraint_valid boolean DEFAULT true NOT NULL
    , ignore_default_data boolean NOT NULL DEFAULT true
    , default_table boolean DEFAULT true
    , date_trunc_interval text
    , maintenance_order int
    , retention_keep_publication boolean NOT NULL DEFAULT false
    , maintenance_last_run timestamptz
    , CONSTRAINT part_config_parent_table_pkey PRIMARY KEY (parent_table)
    , CONSTRAINT positive_premake_check CHECK (premake > 0)
);

CREATE INDEX part_config_type_idx ON @extschema@.part_config (partition_type);
SELECT pg_catalog.pg_extension_config_dump('@extschema@.part_config'::regclass, '');


-- FK set deferrable because create_parent() & create_sub_parent() inserts to this table before part_config
CREATE TABLE @extschema@.part_config_sub (
    sub_parent text
    , sub_control text NOT NULL
    , sub_partition_interval text NOT NULL
    , sub_partition_type text NOT NULL
    , sub_premake int NOT NULL DEFAULT 4
    , sub_automatic_maintenance text NOT NULL DEFAULT 'on'
    , sub_template_table text
    , sub_retention text
    , sub_retention_schema text
    , sub_retention_keep_index boolean NOT NULL DEFAULT true
    , sub_retention_keep_table boolean NOT NULL DEFAULT true
    , sub_epoch text NOT NULL DEFAULT 'none'
    , sub_constraint_cols text[]
    , sub_optimize_constraint int NOT NULL DEFAULT 30
    , sub_infinite_time_partitions boolean NOT NULL DEFAULT false
    , sub_jobmon boolean NOT NULL DEFAULT true
    , sub_inherit_privileges boolean DEFAULT false
    , sub_constraint_valid boolean DEFAULT true NOT NULL
    , sub_ignore_default_data boolean NOT NULL DEFAULT true
    , sub_default_table boolean default true
    , sub_date_trunc_interval TEXT
    , sub_maintenance_order int
    , sub_retention_keep_publication boolean NOT NULL DEFAULT false
    , CONSTRAINT part_config_sub_pkey PRIMARY KEY (sub_parent)
    , CONSTRAINT part_config_sub_sub_parent_fkey FOREIGN KEY (sub_parent) REFERENCES @extschema@.part_config (parent_table) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED
    , CONSTRAINT positive_premake_check CHECK (sub_premake > 0)
);
SELECT pg_catalog.pg_extension_config_dump('@extschema@.part_config_sub'::regclass, '');

-- Ensure the control column cannot be one of the additional constraint columns.
ALTER TABLE @extschema@.part_config ADD CONSTRAINT control_constraint_col_chk CHECK ((constraint_cols @> ARRAY[control]) <> true);
ALTER TABLE @extschema@.part_config_sub ADD CONSTRAINT control_constraint_col_chk CHECK ((sub_constraint_cols @> ARRAY[sub_control]) <> true);

ALTER TABLE @extschema@.part_config ADD CONSTRAINT retention_schema_not_empty_chk CHECK (retention_schema <> '');
ALTER TABLE @extschema@.part_config_sub ADD CONSTRAINT retention_schema_not_empty_chk CHECK (sub_retention_schema <> '');

/*
 * Custom view to help improve privilege lookups for pg_partman.
 * information_schema is a performance bottleneck since indexes aren't being used properly.
 */
CREATE VIEW @extschema@.table_privs AS
    SELECT u_grantor.rolname AS grantor,
           grantee.rolname AS grantee,
           nc.nspname AS table_schema,
           c.relname AS table_name,
           c.prtype AS privilege_type
    FROM (
            SELECT oid, relname, relnamespace, relkind, relowner, (aclexplode(coalesce(relacl, acldefault('r', relowner)))).* FROM pg_class
         ) AS c (oid, relname, relnamespace, relkind, relowner, grantor, grantee, prtype, grantable),
         pg_namespace nc,
         pg_roles u_grantor,
         (
           SELECT oid, rolname FROM pg_roles
           UNION ALL
           SELECT 0::oid, 'PUBLIC'
         ) AS grantee (oid, rolname)
    WHERE c.relnamespace = nc.oid
          AND c.relkind IN ('r', 'v', 'p')
          AND c.grantee = grantee.oid
          AND c.grantor = u_grantor.oid
          AND c.prtype IN ('INSERT', 'SELECT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')
          AND (pg_has_role(u_grantor.oid, 'USAGE')
               OR pg_has_role(grantee.oid, 'USAGE')
               OR grantee.rolname = 'PUBLIC' );

-- Put constraint functions & definitions here because having them in a separate file makes the ordering of their creation harder to control. Some require the above tables to exist first.

/*
 * Check for valid config values for automatic maintenance
 * (not boolean to allow future values)
 */
CREATE FUNCTION @extschema@.check_automatic_maintenance_value (p_automatic_maintenance text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
v_result    boolean;
BEGIN
    SELECT p_automatic_maintenance IN ('on', 'off') INTO v_result;
    RETURN v_result;
END
$$;

ALTER TABLE @extschema@.part_config
ADD CONSTRAINT part_config_automatic_maintenance_check
CHECK (@extschema@.check_automatic_maintenance_value(automatic_maintenance));

ALTER TABLE @extschema@.part_config_sub
ADD CONSTRAINT part_config_sub_automatic_maintenance_check
CHECK (@extschema@.check_automatic_maintenance_value(sub_automatic_maintenance));


/*
 * Check function for config table epoch types
 */
CREATE FUNCTION @extschema@.check_epoch_type (p_type text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER
    SET search_path TO pg_catalog, pg_temp
    AS $$
DECLARE
v_result    boolean;
BEGIN
    SELECT p_type IN ('none', 'seconds', 'milliseconds', 'nanoseconds') INTO v_result;
    RETURN v_result;
END
$$;


ALTER TABLE @extschema@.part_config
ADD CONSTRAINT part_config_epoch_check
CHECK (@extschema@.check_epoch_type(epoch));

ALTER TABLE @extschema@.part_config_sub
ADD CONSTRAINT part_config_sub_epoch_check
CHECK (@extschema@.check_epoch_type(sub_epoch));


/*
 * Check for valid config table partition types
 */
-- Allow hash in future update
CREATE FUNCTION @extschema@.check_partition_type (p_type text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER
    SET search_path TO pg_catalog, pg_temp
    AS $$
DECLARE
v_result    boolean;
BEGIN
    SELECT p_type IN ('range', 'list') INTO v_result;
    RETURN v_result;
END
$$;


ALTER TABLE @extschema@.part_config
ADD CONSTRAINT part_config_type_check
CHECK (@extschema@.check_partition_type(partition_type));

ALTER TABLE @extschema@.part_config_sub
ADD CONSTRAINT part_config_sub_type_check
CHECK (@extschema@.check_partition_type(sub_partition_type));
