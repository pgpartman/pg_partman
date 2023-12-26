5.0.0 & 5.0.1
=============
UPGRADE NOTES
-------------
 - The upgrade to 5.x had to be split into two parts to allow certain transaction limiting conditions to be met. Please see [pg_partman_5.0.1_upgrade.md](doc/pg_partman_5.0.1_upgrade.md) if you run into any errors concerning triggers when trying to update. There is no standalone version of 5.0.0 for pg_partman any longer and all users should update to 5.0.1.
    - If you have already successfully upgraded to version 5.0.0, the update to 5.0.1 will not introduce any changes. The new minor version is to allow for the staged upgrade.
 - It is recommended that you take a backup of the `part_config` and `part_config_sub` tables before upgrading just to ensure they can be restored in case there are any issues. These tables are recreated as part of the upgrade.
   - If you see any errors about the following tables existing during an upgrade attempt, please review their content and ensure you do not need any of the backed up pre-5.x configuration data they contain. Drop them if not needed and try the upgrade again: `part_config_pre_500_data`, `part_config_sub_pre_500_data`
 - Many thanks to all the people that have helped with testing and code review during 5.x development. In particular...
    - Leigh Downs and the team at Crunchy Data for extensive testing
    - vitaly-burovoy on Github for some amazing optimizations and code review
    - andyatkinson on Github for documentation review and pointing out my antiquated usage of the term "native" now that there's only one partitioning method supported
    - hyde1 on Github for finding the upgrade issue and a simpler upgrade method for 5.0.1
    - And as always to [pgTAP](https://pgtap.org/) for making testing so much easier

BREAKING CHANGES
----------------
 - Removed trigger-based partitioning support. All partitioning is now done using built-in declarative partitioning. The partitioning `type` in pg_partman will now refer to the types of delcarative partitioning that are supported. As of 5.0.1, only `range` is supported, but others are in development (Github Issue #490).
    - See [migrate_to_declarative.md](doc/migrate_to_declarative.md) for assistance on migrating off trigger-based partitioning.
 - Many functions have had their parameters altered, renamed, rearranged or removed. These should be more consistent across the code-base now. Please review ALL calls to pg_partman functions to ensure that your parameter names and values have been updated to match the changes.
    - The `part_config` and `part_config_sub` tables have had some columns removed and rearranged to only contain supported features.
 - Due to a majority of extension objects being dropped & recreated, privileges on the extension objects ARE NOT being preserved as they have been done with past extension updates. Ensure existing privileges are recorded before upgrading pg_partman and are regranted/revoked after the upgrade is complete. Check the following system catalogs for privilege information for pg_partman objects: `information_schema.routine_privileges` & `information_schema.table_privileges`
 - Some specialized time-based interval types have been deprecated. See [pg_partman_5.0.1_upgrade.md](doc/pg_partman_5.0.1_upgrade.md) for additional guidance on migrating unsupported partition methods to supported ones.
    - All time-based interval values must now be valid values for the interval data type. The previous weekly, hourly, daily, etc interval values are no longer supported.
    - Removed specialized quarterly partitioning (see [5.0.1 migration doc](doc/pg_partman_5.0.1_upgrade.md)).
    - Removed specialized weekly partitioning with ISO style week numbers (see [5.0.1 migration doc](doc/pg_partman_5.0.1_upgrade.md)).
    - Hourly partitioning now has seconds on the child partition suffix. Migration for this is not necessary, but just be aware that any new partition sets created with this interval may look different than existing ones from prior pg_partman versions.
 - The minimum required version of PostgreSQL is now 14
    - Required for calling procedures via background worker (Github PR #242).
 - Dropped automatic publication refresh of a partition set that was part of a logical replication subscription. As of PostgreSQL 14, it is no longer possible to call ALTER SUBSCRIPTION ... REFRESH PUBLICATION within a transaction block which means it can no longer be called via the maintenance functions. For now, an independent call with this refresh statement will need to be done on the subscription side of partition sets that are part of logical replication (Github Issue #572).
 - The partition control column being NOT NULL is now fully enforced when making new partition sets.

NEW FEATURES
------------
 - Changed all usage of the term "native" to "declarative" to better match upstream PostgreSQL terminology for built-in partitioning.
 - Simplified all time-based partitioning suffixes to `YYYYMMDD` for intervals greater than or equal to 1 day and `YYYYMMDD_HH24MISS` for intervals less than 1 day. Removed extra underscores to allow longer base partition names. Existing partition suffixes will still be supported, but newly created partition sets will use the new naming patterns by default. It is recommended that migration to the new suffixes is done when possible to ensure future support of possible pg_partman changes. The [documentation](doc/pg_partman_5.0.1_upgrade.md) on migrating the old specialized weekly/quarterly partition sets to be supported in 5.0.1 can be used as guidance for migrating other child table names as well.
 - By default, data in the default partition is now ignored when calculating new child partitions to create. If a new child table's boundaries would include data that exists in the default, this will cause an error during maintenance and must be manually resolved by either removing that data from the default or partitioning it out to the proper child table using the partition_data function/procedure.
    - A flag is available to take default data into consideration, but this should only be used in rare circumstances to correct maintenance issues and should not be left permanently enabled for ideal partition maintenance.
 - Added option to make default table optional during partition creation (`p_default_table`) (Github Issue #489).
 - As of PostgreSQL 13, newly created child tables in a partition set that is part of a logical replication PUBLICATION are automatically added to that PUBLICATION. Therefore the "publications" array configuration in the pg_partman configuration tables was removed. Simply make sure the parent table is a part of the necessary publications and it will be automatically handled by core PostgreSQL from now on (Github Issue #520)
    - Note the SUBSCRIPTION does not automatically get refreshed to account for new tables added to a published partition set. See note above in BREAKING CHANGES concerning subscription side refreshes.
 - Added support for dropping indexes for partitions moved to another schema as part of retention (Github PR #449).
 - Creating a template table is now optional when calling `create_parent()`. Set `p_template_table` to `false` to skip template table creation. Note this is not a boolean since this parameter is also meant to take a template table name, so the explicit string value `false` must be set (Github Issue #505).
 - Lots of backend optimizations and code simplification

BUG FIXES
---------
 - Edge case with `infinite_time_partitions` fixed. If set to true and data far ahead of "now" was inserted, no new child tables would be created based on the premake.
 - Make errors from `show_partition_info()` clearer (Github Issue #542).
 - Ensure the bgw_type value is properly set in the Background Worker structs (Github Issue #573).


For CHANGELOGs prior to version 5.0.0, see CHANGELOG-pre-5.0.0.txt
