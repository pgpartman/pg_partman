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
    , sub_subscription_refresh text
    , sub_ignore_default_data boolean NOT NULL DEFAULT true
    , sub_default_table boolean default true
    , sub_date_trunc_interval TEXT
    , CONSTRAINT part_config_sub_pkey PRIMARY KEY (sub_parent)
    , CONSTRAINT part_config_sub_sub_parent_fkey FOREIGN KEY (sub_parent) REFERENCES @extschema@.part_config (parent_table) ON DELETE CASCADE ON UPDATE CASCADE DEFERRABLE INITIALLY DEFERRED
    , CONSTRAINT positive_premake_check CHECK (sub_premake > 0)
);
SELECT pg_catalog.pg_extension_config_dump('@extschema@.part_config_sub', '');

-- Ensure the control column cannot be one of the additional constraint columns.
ALTER TABLE @extschema@.part_config_sub ADD CONSTRAINT control_constraint_col_chk CHECK ((sub_constraint_cols @> ARRAY[sub_control]) <> true);
ALTER TABLE @extschema@.part_config_sub ADD CONSTRAINT retention_schema_not_empty_chk CHECK (sub_retention_schema <> '');

ALTER TABLE @extschema@.part_config_sub
ADD CONSTRAINT part_config_sub_automatic_maintenance_check
CHECK (@extschema@.check_automatic_maintenance_value(sub_automatic_maintenance));

ALTER TABLE @extschema@.part_config_sub
ADD CONSTRAINT part_config_sub_epoch_check
CHECK (@extschema@.check_epoch_type(sub_epoch));

ALTER TABLE @extschema@.part_config_sub
ADD CONSTRAINT part_config_sub_type_check
CHECK (@extschema@.check_partition_type(sub_partition_type));
