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
    , subscription_refresh text
    , ignore_default_data boolean NOT NULL DEFAULT true
    , default_table boolean DEFAULT true
    , date_trunc_interval text
    , CONSTRAINT part_config_parent_table_pkey PRIMARY KEY (parent_table)
    , CONSTRAINT positive_premake_check CHECK (premake > 0)
);
CREATE INDEX part_config_type_idx ON @extschema@.part_config (partition_type);
SELECT pg_catalog.pg_extension_config_dump('@extschema@.part_config', '');

-- Ensure the control column cannot be one of the additional constraint columns.
ALTER TABLE @extschema@.part_config ADD CONSTRAINT control_constraint_col_chk CHECK ((constraint_cols @> ARRAY[control]) <> true);
ALTER TABLE @extschema@.part_config ADD CONSTRAINT retention_schema_not_empty_chk CHECK (retention_schema <> '');

ALTER TABLE @extschema@.part_config
ADD CONSTRAINT part_config_automatic_maintenance_check
CHECK (@extschema@.check_automatic_maintenance_value(automatic_maintenance));

ALTER TABLE @extschema@.part_config
ADD CONSTRAINT part_config_epoch_check
CHECK (@extschema@.check_epoch_type(epoch));

ALTER TABLE @extschema@.part_config
ADD CONSTRAINT part_config_type_check
CHECK (@extschema@.check_partition_type(partition_type));
