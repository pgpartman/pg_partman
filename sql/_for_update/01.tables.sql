-- IMPORTANT NOTE: It is recommended that you take a backup of the part_config and part_config_sub tables before upgrading just to ensure they can be restored in case there are any issues. These tables are recreated as part of the upgrade.
    -- If you see any errors about the following tables existing during an upgrade attempt, please review their content and ensure you do not need any of the backed up pre-5.x configuration data they contain. Drop them if not needed and try the upgrade again: part_config_pre_500_data, part_config_sub_pre_500_data

-- (Breaking Change) Removed trigger-based partitioning support. All partitioning is now done using built-in (native) declarative partitioning. The partitioning 'type' in pg_partman will now refer to the types of delcarative partitioning that are supported. As of 5.0.0, only 'range' is supported, but others are in development.

-- (Breaking Change) Many functions have had their parameters altered, renamed, rearranged or removed. These should be more consistent across the code-base now. Please review ALL calls to pg_partman functions to ensure that your parameter names and values have been updated to match the changes.

-- (Breaking Change) Due to a majority of extension objects being dropped & recreated, privileges on the extension objects ARE NOT being preserved as they have been done with past extension updates. Ensure existing privileges are recorded before upgrading pg_partman and are regranted/revoked after the upgrade is complete. Check the following system catalogs for privilege information for pg_partman objects: information_schema.routine_privileges & information_schema.table_privileges

-- (Breaking Change) Some specialized time-based interval types have been deprecated.
    -- All time-based interval values must now be valid values for the interval data type. The previous weekly, hourly, daily, etc interval values are no longer supported.
    -- Removed specialized quarterly partitioning (see new migration doc).
    -- Removed specialized weekly partitioning with ISO style week numbers (see new migration doc).
    -- Hourly partitioning now has seconds on the child partition suffix. Migration for this is not necessary, but just be aware that any new partition sets created with this interval may look different than existing ones from prior pg_partman versions.

-- The minimum required version of PostgreSQL is now 14

-- Simplified all time-based partitioning suffixes to YYYYMMDD for intervals greater than or equal to 1 day and YYYYMMDD_HH24MISS for intervals less than 1 day. Removed extra underscores to allow longer base partition names. Existing partition suffixes will still be supported, but newly created partition sets will use the new naming patterns by default. It is recommended that migration to the new suffixes is done when possible to ensure future support of possible pg_partman changes. The documentation on migrating the old specialized weekly/quarterly partition sets to be supported in 5.0.0 can be used as guidance for migrating other child tablenames as well.

-- By default, data in the default partition is now ignored when calculating new child partitions to create. If a new child table's boundaries would include data that exists in the default, this will cause an error during maintenance and must be manually resolved by either removing that data from the default or partitioning it out to the proper child table using the partition_data function/procedure.
    -- A flag is available to take default data into consideration, but this should only be used in rare circumstances to correct maintenance issues and should not be left permanently enabled.

-- As of PostgreSQL 13, newly created child tables in a partition set that is part of a logical repication PUBLICATION are automatically added to that PUBLICATION. Therefore the "publications" array configuration in the pg_partman configuration tables was removed. Simply make sure the parent table is a part of the necessary publications and it will be natively handled from now on.
    -- Note The SUBSCRIPTION does not automatically get refreshed to account for new tables added to a published partition set. If pg_partman is also managing your partition set on the SUBSCRIPTION side, ensure the "subscription_refresh" flag in the configuration table is set to true so that maintenance will automatically run to add the new tables to the subscription.

-- Added support for dropping indexes for partitions moved to another schema as part of retention

-- Creating a template table is now optional when calling create_parent(). Set p_template_table to 'false' to skip template table creation. Note this is not a boolean since this parameter is also meant to take a template table name, so the explicit string value 'false' must be set.

-- Edge case with infinite_time_partitions fixed. If set to true and data far ahead of "now" was inserted, no new child tables would be created based on the premake.

-- Many thanks to Leigh Downs w/ Crunchy Data for the extensive testing done during the 5.x development cycle!

-- #### Ugrade exceptions ####
DO $upgrade_partman$
DECLARE
v_count     int;
BEGIN
    SELECT count(*) INTO v_count FROM @extschema@.part_config WHERE partition_type = 'partman';
    IF v_count > 0 THEN
      RAISE EXCEPTION 'One or more partition sets are configured for trigger-based partitioning which is not supported in version 5.0.0 or greater. See documentation for migrating to native partitioning before upgrading.';
    END IF;
END
$upgrade_partman$;

DO $upgrade_datetime_string$
DECLARE
v_count     int;
BEGIN
    SELECT count(*) INTO v_count FROM @extschema@.part_config WHERE datetime_string IN ('YYYY"q"Q', 'IYYY"w"IW');
    IF v_count > 0 THEN
      RAISE WARNING 'One or more partition sets are configured for quarterly or ISO weekly partitioning which is not supported in version 5.0.0 or greater. See documentation for migrating to native intervals. This migration can and should be done after upgrading to ensure new partition suffixes are used.';
    END IF;
END
$upgrade_datetime_string$;


-- #### Table alterations ####
DROP TABLE @extschema@.custom_time_partitions;

ALTER TABLE @extschema@.part_config ALTER ignore_default_data SET DEFAULT true;

-- Do NOT drop these tables until upgrade has completed successfully (see end of this update file)
--      If they exist, a previous upgrade may have been attempted and
--      we don't want to lose data that user may have backed up and need for recovery.
CREATE UNLOGGED TABLE @extschema@.part_config_pre_500_data (LIKE @extschema@.part_config);
CREATE UNLOGGED TABLE @extschema@.part_config_sub_pre_500_data (LIKE @extschema@.part_config_sub);

INSERT INTO @extschema@.part_config_sub_pre_500_data (
    sub_parent
    , sub_partition_type
    , sub_control
    , sub_partition_interval
    , sub_constraint_cols
    , sub_premake
    , sub_optimize_trigger
    , sub_optimize_constraint
    , sub_epoch
    , sub_inherit_fk
    , sub_retention
    , sub_retention_schema
    , sub_retention_keep_table
    , sub_retention_keep_index
    , sub_infinite_time_partitions
    , sub_automatic_maintenance
    , sub_jobmon
    , sub_trigger_exception_handling
    , sub_upsert
    , sub_trigger_return_null
    , sub_template_table
    , sub_inherit_privileges
    , sub_constraint_valid
    , sub_subscription_refresh
    , sub_date_trunc_interval
    , sub_ignore_default_data
)
SELECT
    sub_parent
    , sub_partition_type
    , sub_control
    , sub_partition_interval
    , sub_constraint_cols
    , sub_premake
    , sub_optimize_trigger
    , sub_optimize_constraint
    , sub_epoch
    , sub_inherit_fk
    , sub_retention
    , sub_retention_schema
    , sub_retention_keep_table
    , sub_retention_keep_index
    , sub_infinite_time_partitions
    , sub_automatic_maintenance
    , sub_jobmon
    , sub_trigger_exception_handling
    , sub_upsert
    , sub_trigger_return_null
    , sub_template_table
    , sub_inherit_privileges
    , sub_constraint_valid
    , sub_subscription_refresh
    , sub_date_trunc_interval
    , sub_ignore_default_data
FROM @extschema@.part_config_sub;


INSERT INTO @extschema@.part_config_pre_500_data (
    parent_table
    , control
    , partition_type
    , partition_interval
    , constraint_cols
    , premake
    , optimize_trigger
    , optimize_constraint
    , epoch
    , inherit_fk
    , retention
    , retention_schema
    , retention_keep_table
    , retention_keep_index
    , infinite_time_partitions
    , datetime_string
    , automatic_maintenance
    , jobmon
    , sub_partition_set_full
    , undo_in_progress
    , trigger_exception_handling
    , upsert
    , trigger_return_null
    , template_table
    , publications
    , inherit_privileges
    , constraint_valid
    , subscription_refresh
    , drop_cascade_fk
    , ignore_default_data
)
SELECT
    parent_table
    , control
    , partition_type
    , partition_interval
    , constraint_cols
    , premake
    , optimize_trigger
    , optimize_constraint
    , epoch
    , inherit_fk
    , retention
    , retention_schema
    , retention_keep_table
    , retention_keep_index
    , infinite_time_partitions
    , datetime_string
    , automatic_maintenance
    , jobmon
    , sub_partition_set_full
    , undo_in_progress
    , trigger_exception_handling
    , upsert
    , trigger_return_null
    , template_table
    , publications
    , inherit_privileges
    , constraint_valid
    , subscription_refresh
    , drop_cascade_fk
    , ignore_default_data
FROM @extschema@.part_config;

DROP TABLE @extschema@.part_config_sub;
DROP TABLE @extschema@.part_config;

-- Allow list/hash in future update
CREATE OR REPLACE FUNCTION @extschema@.check_partition_type (p_type text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE SECURITY DEFINER
    SET search_path TO pg_catalog, pg_temp
    AS $$
DECLARE
v_result    boolean;
BEGIN
    SELECT p_type IN ('range') INTO v_result;
    RETURN v_result;
END
$$;
