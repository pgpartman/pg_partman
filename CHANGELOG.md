5.0.0
=====
UPGRADE NOTES
-------------
 - It is recommended that you take a backup of the part_config and part_config_sub tables before upgrading just to ensure they can be restored in case there are any issues. These tables are recreated as part of the upgrade.
 - If you see any errors about the following tables existing during an upgrade attempt, please review their content and ensure you do not need any of the backed up pre-5.x configuration data they contain. Drop them if not needed and try the upgrade again: part_config_pre_500_data, part_config_sub_pre_500_data
 - For CHANGELOG notes prior to version 5.0.0, please see [CHANGELOG-pre-5.0.0.txt](CHANGELOG-pre-5.0.0.txt).
 - Many thanks to all the people that have help with testing and code review during 5.x development. In particular...
    - Leigh Downs and the team at Crunchy Data for extensive testing
    - vitaly-burovoy on Github for some amazing optimizations and code review
    - andyatkinson on Github for documentation review and pointing out my antiquated usage of the term "native" now that there's only one partitioning method supported
    - And as always to [pgTAP](https://pgtap.org/) for making testing so much easier

BREAKING CHANGES
----------------
 - Removed trigger-based partitioning support. All partitioning is now done using built-in declarative partitioning. The partitioning 'type' in pg_partman will now refer to the types of delcarative partitioning that are supported. As of 5.0.0, only 'range' is supported, but others are in development.
    - See [migrate_to_declarative.md](doc/migrate_to_declarative.md) for assistance on migrating off trigger-based partitioning.
 - Many functions have had their parameters altered, renamed, rearranged or removed. These should be more consistent across the code-base now. Please review ALL calls to pg_partman functions to ensure that your parameter names and values have been updated to match the changes.
    - The `part_config` and `part_config_sub` tables have also had some columns removed and rearranged to only contain supported features.
 - Due to a majority of extension objects being dropped & recreated, privileges on the extension objects ARE NOT being preserved as they have been done with past extension updates. Ensure existing privileges are recorded before upgrading pg_partman and are regranted/revoked after the upgrade is complete. Check the following system catalogs for privilege information for pg_partman objects: information_schema.routine_privileges & information_schema.table_privileges
 - Some specialized time-based interval types have been deprecated. See [pg_partman_5.0.0_upgrade.md](doc/pg_partman_5.0.0_upgrade.md) for additional guidance on migrating unsupported partition methods to supported ones.
    - All time-based interval values must now be valid values for the interval data type. The previous weekly, hourly, daily, etc interval values are no longer supported.
    - Removed specialized quarterly partitioning (see new migration doc).
    - Removed specialized weekly partitioning with ISO style week numbers (see new migration doc).
    - Hourly partitioning now has seconds on the child partition suffix. Migration for this is not necessary, but just be aware that any new partition sets created with this interval may look different than existing ones from prior pg_partman versions.
 - The minimum required version of PostgreSQL is now 14
    - Required for calling procedures via background worker

NEW FEATURES
------------
 - Changed all usage of the term "native" to "declarative" to better match upstream PostgreSQL terminology for built-in partitioning.
 - Simplified all time-based partitioning suffixes to YYYYMMDD for intervals greater than or equal to 1 day and YYYYMMDD_HH24MISS for intervals less than 1 day. Removed extra underscores to allow longer base partition names. Existing partition suffixes will still be supported, but newly created partition sets will use the new naming patterns by default. It is recommended that migration to the new suffixes is done when possible to ensure future support of possible pg_partman changes. The documentation on migrating the old specialized weekly/quarterly partition sets to be supported in 5.0.0 can be used as guidance for migrating other child table names as well.
 - By default, data in the default partition is now ignored when calculating new child partitions to create. If a new child table's boundaries would include data that exists in the default, this will cause an error during maintenance and must be manually resolved by either removing that data from the default or partitioning it out to the proper child table using the partition_data function/procedure.
    - A flag is available to take default data into consideration, but this should only be used in rare circumstances to correct maintenance issues and should not be left permanently enabled.
 - Added option to make default table optional during partition creation (p_default_table).
 - As of PostgreSQL 13, newly created child tables in a partition set that is part of a logical repication PUBLICATION are automatically added to that PUBLICATION. Therefore the "publications" array configuration in the pg_partman configuration tables was removed. Simply make sure the parent table is a part of the necessary publications and it will be automatically handled by core PostgreSQL from now on.
    - Note The SUBSCRIPTION does not automatically get refreshed to account for new tables added to a published partition set. If pg_partman is also managing your partition set on the SUBSCRIPTION side, ensure the "subscription_refresh" flag in the configuration table is set to true so that maintenance will automatically add the new tables to the subscription.
 - Added support for dropping indexes for partitions moved to another schema as part of retention
 - Creating a template table is now optional when calling create_parent(). Set p_template_table to 'false' to skip template table creation. Note this is not a boolean since this parameter is also meant to take a template table name, so the explicit string value 'false' must be set.

BUG FIXES
---------
 - Edge case with infinite_time_partitions fixed. If set to true and data far ahead of "now" was inserted, no new child tables would be created based on the premake.
