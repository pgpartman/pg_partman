-- IMPORTANT NOTE: The initial version of pg_partman 5 had to be split into two updates due to changing both the data in the config table as well as adding constraints on that data. Depending on the data contained in the config table, doing this in a single-transaction update may not work (you may see an error about pending trigger events). If this is the case, please update to version 5.0.1 in a separate transaction from your update to 5.0.0. Example:

    /*
        BEGIN;
        ALTER EXTENSION pg_partman UPDATE TO '5.0.0';
        COMMIT;

        BEGIN;
        ALTER EXTENSION pg_partman UPDATE TO '5.0.1';
        COMMIT;
    */

-- Update 5.0.1 MUST be installed for version 5.x of pg_partman to work properly. As long as these updates are run within a few seconds of each other, there should be no issues.

-- Only recreate constraints if they don't already exist from a previous 5.0.0 update before 5.0.1 was available
DO $$
DECLARE
v_exists    text;
BEGIN

    SELECT conname INTO v_exists
    FROM pg_catalog.pg_constraint t
    JOIN pg_catalog.pg_class c ON t.conrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE t.conname = 'control_constraint_col_chk'
    AND c.relname = 'part_config'
    AND n.nspname = '@extschema@';

    IF v_exists IS NULL THEN
        EXECUTE format('
            ALTER TABLE @extschema@.part_config
            ADD CONSTRAINT control_constraint_col_chk
            CHECK ((constraint_cols @> ARRAY[control]) <> true)
            ');
    END IF;
    v_exists := NULL;

    SELECT conname INTO v_exists
    FROM pg_catalog.pg_constraint t
    JOIN pg_catalog.pg_class c ON t.conrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE t.conname = 'control_constraint_col_chk'
    AND c.relname = 'part_config_sub'
    AND n.nspname = '@extschema@';

    IF v_exists IS NULL THEN
        EXECUTE format('
            ALTER TABLE @extschema@.part_config_sub
            ADD CONSTRAINT control_constraint_col_chk
            CHECK ((sub_constraint_cols @> ARRAY[sub_control]) <> true)
            ');
    END IF;
    v_exists := NULL;

    SELECT conname INTO v_exists
    FROM pg_catalog.pg_constraint t
    JOIN pg_catalog.pg_class c ON t.conrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE t.conname = 'retention_schema_not_empty_chk'
    AND c.relname = 'part_config'
    AND n.nspname = '@extschema@';

    IF v_exists IS NULL THEN
        EXECUTE format('
            ALTER TABLE @extschema@.part_config
            ADD CONSTRAINT retention_schema_not_empty_chk
            CHECK (retention_schema <> %L)
            ', '');
    END IF;
    v_exists := NULL;

    SELECT conname INTO v_exists
    FROM pg_catalog.pg_constraint t
    JOIN pg_catalog.pg_class c ON t.conrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE t.conname = 'retention_schema_not_empty_chk'
    AND c.relname = 'part_config_sub'
    AND n.nspname = '@extschema@';

    IF v_exists IS NULL THEN
        EXECUTE format('
            ALTER TABLE @extschema@.part_config_sub
            ADD CONSTRAINT retention_schema_not_empty_chk
            CHECK (sub_retention_schema <> %L)'
            , '');
    END IF;
    v_exists := NULL;

    SELECT conname INTO v_exists
    FROM pg_catalog.pg_constraint t
    JOIN pg_catalog.pg_class c ON t.conrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE t.conname = 'part_config_automatic_maintenance_check'
    AND c.relname = 'part_config'
    AND n.nspname = '@extschema@';

    IF v_exists IS NULL THEN
        EXECUTE format('
            ALTER TABLE @extschema@.part_config
            ADD CONSTRAINT part_config_automatic_maintenance_check
            CHECK (@extschema@.check_automatic_maintenance_value(automatic_maintenance));
            ');
    END IF;
    v_exists := NULL;

    SELECT conname INTO v_exists
    FROM pg_catalog.pg_constraint t
    JOIN pg_catalog.pg_class c ON t.conrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE t.conname = 'part_config_sub_automatic_maintenance_check'
    AND c.relname = 'part_config_sub'
    AND n.nspname = '@extschema@';

    IF v_exists IS NULL THEN
        EXECUTE format('
            ALTER TABLE @extschema@.part_config_sub
            ADD CONSTRAINT part_config_sub_automatic_maintenance_check
            CHECK (@extschema@.check_automatic_maintenance_value(sub_automatic_maintenance));
            ');
    END IF;
    v_exists := NULL;

    SELECT conname INTO v_exists
    FROM pg_catalog.pg_constraint t
    JOIN pg_catalog.pg_class c ON t.conrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE t.conname = 'part_config_epoch_check'
    AND c.relname = 'part_config'
    AND n.nspname = '@extschema@';

    IF v_exists IS NULL THEN
        EXECUTE format('
            ALTER TABLE @extschema@.part_config
            ADD CONSTRAINT part_config_epoch_check
            CHECK (@extschema@.check_epoch_type(epoch));
            ');
    END IF;
    v_exists := NULL;

    SELECT conname INTO v_exists
    FROM pg_catalog.pg_constraint t
    JOIN pg_catalog.pg_class c ON t.conrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE t.conname = 'part_config_sub_epoch_check'
    AND c.relname = 'part_config_sub'
    AND n.nspname = '@extschema@';

    IF v_exists IS NULL THEN
        EXECUTE format('
            ALTER TABLE @extschema@.part_config_sub
            ADD CONSTRAINT part_config_sub_epoch_check
            CHECK (@extschema@.check_epoch_type(sub_epoch));
            ');
    END IF;
    v_exists := NULL;

    SELECT conname INTO v_exists
    FROM pg_catalog.pg_constraint t
    JOIN pg_catalog.pg_class c ON t.conrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE t.conname = 'part_config_type_check'
    AND c.relname = 'part_config'
    AND n.nspname = '@extschema@';

    IF v_exists IS NULL THEN
        EXECUTE format('
            ALTER TABLE @extschema@.part_config
            ADD CONSTRAINT part_config_type_check
            CHECK (@extschema@.check_partition_type(partition_type));
            ');
    END IF;
    v_exists := NULL;

    SELECT conname INTO v_exists
    FROM pg_catalog.pg_constraint t
    JOIN pg_catalog.pg_class c ON t.conrelid = c.oid
    JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid
    WHERE t.conname = 'part_config_sub_type_check'
    AND c.relname = 'part_config_sub'
    AND n.nspname = '@extschema@';

    IF v_exists IS NULL THEN
        EXECUTE format('
            ALTER TABLE @extschema@.part_config_sub
            ADD CONSTRAINT part_config_sub_type_check
            CHECK (@extschema@.check_partition_type(sub_partition_type));
            ');
    END IF;
    v_exists := NULL;


END
$$;
