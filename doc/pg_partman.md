PostgreSQL Partition Manager Extension (`pg_partman`)
=====================================================

About
-----
PostgreSQL Partition Manager is an extension to help make managing time or number/id based table partitioning easier. It has many options, but usually only a few are needed, so it's much easier to use than it may first appear (and definitely easier than implementing it yourself).

As of version 5.0.1, the minimum version of PostgreSQL required is 14 and trigger-based partitioning is no longer supported. All partitioning is done using built-in declarative partitioning. Currently only ranged partitioning is supported for time- and number-based intervals. Version 4.x of pg_partman, which still has trigger-based support, is no longer in active development and will only be receiving critical bug fixes for a limited time. If partitioning is a critical part of your infrastructure, please make plans to upgrade in the near future.

A default partition to catch data outside the existing child boundaries is automatically created for all partition sets. The `check_default()` function provides monitoring for any data getting inserted into the default table and the `partition_data_`* set of functions can easily partition that data for you if it is valid data. That is much easier than automatically creating new child tables on demand and having to clean up potentially hundreds or thousands of unwanted partitions. And also better than throwing an error and losing the data!

Note that future child table creation is based on the data currently in the partition set and, by default, ignores data in the default. It is recommended that you set the `premake` value high enough to encompass your expected data range being inserted. See below for further explanations on these configuration values.

If you have an existing partition set and you'd like to migrate it to pg_partman, please see the [migrate_to_partman.md](migrate_to_partman.md) file in the doc folder.

### Child Table Property Inheritance

For this extension, most of the attributes of the child partitions are all obtained from the parent table. With declarative partitioning, certain features are not able to be inherited from the parent depending on the version of PostgreSQL. So pg_partman uses a template table instead. The following table matrix shows how certain property inheritances are managed with pg_partman. The number given is the version of PostgreSQL. If a property is not listed here, then assume it is managed via the parent.

| Feature                                           | Parent Inheritance    | Template Inheritance  |
| ----------                                        | --------------------- | --------------------- |
| non-partition column primary key                  |                       |  14+                  |
| non-partition column unique index                 |                       |  14+                  |
| non-partition column unique index tablespace      |                       |  14+                  |
| unlogged table state*                             |                       |  14+                  |
| non-unique indexes                                | 14+                   |                       |
| privileges/ownership                              | 14+                   |                       |

If a property is managed via the template table, it likely will not be retroactively applied to all existing child tables if that property is changed. It will apply to any newly created children, but will have to be manually applied to any existing children.

Privileges & ownership are NOT inherited by default. If enabled by pg_partman, note that this inheritance is only at child table creation and isn't automatically retroactive when changed (see `reapply_privileges()`). Unless you need direct access to the child tables, this should not be needed. You can set the `inherit_privileges` option if this is needed (see config table information below).  

If you are using the IDENTITY feature for sequences, the automatic generation of new sequence values using this feature is only supported when data is inserted through the parent table, not directly into the children.

IMPORTANT NOTES:

 * The template table feature is only a temporary solution to help speed up declarative partitioning adoption. As things are handled better in core, the use of the template table will be phased out quickly from pg_partman. If a feature that was managed by the template is supported in core in the future, it will eventually be removed from template management in pg_partman, so please plan ahead for that during major version upgrading if it applies to you.

 * The UNLOGGED status is managed via pg_partman's template due to an inconsistency in the way the property is handled when either enabling or disabling UNLOGGED on the parent table of a partition set. That property does not actually change on the parent table when the ALTER command is written so new child tables will continue to use the property that existed before. So if you wanted to change a partition set from UNLOGGED to LOGGED for all future children, it does not work. With the property now being managed on the template table, changing it there will allow the change to propagate to newly created children. Pre-existing child tables will have to be changed manually, but that has always been the case. See reported bug at https://www.postgresql.org/message-id/flat/15954-b61523bed4b110c4%40postgresql.org

### Time Zones

It is important to ensure that the time zones for all systems that will be running pg_partman maintenance operations are consistent, especially when running time-based partitioning. The calls to pg_partman functions will use the time zone that is set by the client at the time the functions are called. This is consistent with the way libpq clients work in general.

In general, it is highly recommended to always run your database system in UTC time. It makes handling any time-related issues tremendously easier and especially to overcome issues that are currently not possible to solve due to Daylight Saving Time (DST) changes. In addition to this, also ensure the client that will be creating partition sets and running the maintenance calls is also set to UTC. For example, trying to partition hourly will either break when the time changes or skip creating a child table.

### Subpartitioning

Subpartitioning with multiple levels is supported, but it is of very limited use in PostgreSQL and provides next to NO PERFORMANCE BENEFIT outside of extremely large data in a single partition set (100s of terabytes, petabytes). If you're looking for performance benefits, adjust your partition interval before considering subpartitioning. It's main use is in data organization and retention management.

You can do time->time, id->id, time->id and id->time. There is no set limit on the level of subpartitioning you can do, but be sensible and keep in mind performance considerations on managing many tables in a single inheritance set. Also, if the number of tables in a single partition set gets very high, you may have to adjust the `max_locks_per_transaction` postgresql.conf setting above the default of 64. Otherwise you may run into shared memory issues or even crash the cluster. If you have contention issues when `run_maintenance()` is called for general maintenance of all partition sets, you can set the **`automatic_maintenance`** column in the **`part_config`** table to false if you do not want that general call to manage your subpartition set. But you must then call `run_maintenance(parent_table)` directly, and often enough, to have to future partitions made. You can use the run_maintenance_proc() procedure instead of the base function to cause less contention issues since it automatically commits after each partition set's maintenance.

PUBLICATION/SUBSCRIPTION for logical replication is NOT supported with subpartitioning.

See the `create_sub_parent()` & `run_maintenance()` functions below for more information.

### Retention

If you don't need to keep data in older partitions, a retention system is available to automatically drop unneeded child partitions. By default, they are only uninherited/detached not actually dropped, but that can be configured if desired. There is also a method available to dump the tables out if they don't need to be in the database anymore but still need to be kept. To set the retention policy, enter either an interval or integer value into the **retention** column of the **part_config** table. For time-based partitioning, the interval value will set that any partitions containing only data older than that will be dropped (including safely handling cases where the retention interval is not a multiple of the partition size). For id-based partitioning, the integer value will set that any partitions with an id value less than the current maximum id value minus the retention value will be dropped. For example, if the current max id is 100 and the retention value is 30, any partitions with id values less than 70 will be dropped. The current maximum id value at the time the drop function is run is always used.
Keep in mind that for subpartition sets, when a parent table has a child dropped, if that child table is in turn partitioned, the drop is a CASCADE and ALL child tables down the entire inheritance tree will be dropped. Also note that a partition set managed by pg_partman must always have at least one child, so retention will never drop the last child table in a set.

### Constraint Exclusion

One of the big advantages of partitioning is a feature called **constraint exclusion** (see docs for explanation of functionality and examples http://www.postgresql.org/docs/current/static/ddl-partitioning.html#DDL-PARTITIONING-CONSTRAINT-EXCLUSION). The problem with most partitioning setups however, is that this will only be used on the partitioning control column. If you use a WHERE condition on any other column in the partition set, a scan across all child tables will occur unless there are also constraints on those columns. And predicting what a column's values will be to pre-create constraints can be very hard or impossible. `pg_partman` has a feature to apply constraints on older tables in a partition set that no longer have any edits done to them ("old" being defined as older than the `optimize_constraint` config value). It checks the current min/max values in the given columns and then applies a constraint to that child table. This can allow the constraint exclusion feature to potentially eliminate scanning older child tables when other columns are used in WHERE conditions. Be aware that this limits being able to edit those columns, but for the situations where it is applicable it can have a tremendous affect on query performance for very large partition sets. So if you are only inserting new data this can be very useful, but if data is regularly being inserted/updated throughout the entire partition set, this is of limited use. Functions for easily recreating constraints are also available if data does end up having to be edited in those older partitions. Note that constraints managed by PG Partman SHOULD NOT be renamed in order to allow the extension to manage them properly for you. For a better example of how this works, please see this blog post: http://www.keithf4.com/managing-constraint-exclusion-in-table-partitioning

Adding these constraints could potentially cause contention with the data contained in those tables and also make pg_partman maintenance take a long time to run. There is a "constraint_valid" column in the part_config(_sub) table to set whether these constraints should be set NOT VALID on creation. While this can make the creation of the constraint(s) nearly instantaneous, constraint exclusion cannot be used until it is validated. This is why constraints are added as valid by default.

NOTE: This may not work with subpartitioning. It will work on the first level of partitioning, but is not guaranteed to work properly on further subpartition sets depending on the interval combinations and the optimize_constraint value. Ex: Weekly -> Daily with a daily optimize_constraint of 7 won't work as expected. Weekly constraints will get created but daily subpartition ones likely will not.

### Time Interval Considerations

The smallest time interval supported is 1 second and the upper limit is bounded by the minimum and maximum timestamp values that PostgreSQL supports (http://www.postgresql.org/docs/current/static/datatype-datetime.html).

When first running `create_parent()` to create a partition set, intervals less than a day round down when determining what the first partition to create will be. Intervals less than 24 hours but greater than 1 minute use the nearest hour rounded down. Intervals less than 1 minute use the nearest minute rounded down. However, enough partitions will be made to support up to what the real current time is. This means that when `create_parent()` is run, more previous partitions may be made than expected and all future partitions may not be made. The first run of `run_maintenance()` will fix the missing future partitions. This happens due to the nature of being able to support custom time intervals. Any intervals greater than or equal to 24 hours should set things up as would be expected.

Keep in mind that for intervals equal to or greater than 100 years, the extension will use the real start of the century or millennium to determine the partition name & constraint rules. For example, the 21st century and 3rd millennium started January 1, 2001 (not 2000). This also means there is no year "0".

For weekly partitions, note that the default "start" of the week will be based on the day of the week that you run `create_parent()`. For example, if you ran it on a Tuesday or Friday, the time boundaries of the child tables would all start on those respective days vs the expected Monday or Sunday start of the week. The easiest way to handle this is to use the `date_trunc()` function to start the weeks on a Monday using the `p_start_partition` parameter to `create_parent()`. Starting on Sundays is likely possible as well, but trickier and outside the scope of the documentation at this time.

```sql
SELECT partman.create_parent('public.time_table', 'col3', '1 week', p_start_partition := to_char(date_trunc('week',CURRENT_TIMESTAMP), 'YYYY-MM-DD HH24:MI:SS'));
```

### Naming Length Limits

PostgreSQL has an object naming length limit of 63 bytes (NOT characters). If you try and create an object with a longer name, it truncates off any characters at the end to fit that limit. This can cause obvious issues with partition names that rely on having a specifically named suffix. PG Partman automatically handles this for all child table names. It will truncate off the existing parent table name to fit the required suffix. Be aware that if you have tables with very long, similar names, you may run into naming conflicts if they are part of separate partition sets. With number based partitioning, be aware that over time the table name will be truncated more and more to fit a longer partition suffix. So while the extension will try and handle this edge case for you, it is recommended to keep table names that will be partitioned as short as possible.

### Unique Constraints

Table inheritance in PostgreSQL does not allow a primary key or unique index/constraint on the parent to apply to all child tables. The constraint is applied to each individual table, but not on the entire partition set as a whole. For example, this means a careless application can cause a primary key value to be duplicated in a partition set. In the mean time, a python script is included with `pg_partman` that can provide monitoring to help ensure the lack of this feature doesn't cause long term harm. See **`check_unique_constraint.py`** in the **Scripts** section.

### Logging/Monitoring

The PG Jobmon extension (https://github.com/omniti-labs/pg_jobmon) is optional and allows auditing and monitoring of partition maintenance. If jobmon is installed and configured properly, it will automatically be used by partman with no additional setup needed. Jobmon can also be turned on or off individually for each partition set by using the `jobmon` column in the **`part_config`** table or with the option to `create_parent()` during initial setup. Note that if you try to partition `pg_jobmon`'s tables you **MUST** set the jobmon option in `create_parent()` to false, otherwise it will be put into a permanent lockwait since `pg_jobmon` will be trying to write to the table it's trying to partition. By default, any function that fails to run successfully 3 consecutive times will cause jobmon to raise an alert. This is why the default pre-make value is set to 4 so that an alert will be raised in time for intervention with no additional configuration of jobmon needed. You can of course configure jobmon to alert before (or later) than 3 failures if needed. If you're running partman in a production environment it is HIGHLY recommended to have jobmon installed and some sort of 3rd-party monitoring configured with it to alert when partitioning fails (Nagios, Circonus, etc).


Background Worker
-----------------
`pg_partman`'s BGW is basically just a scheduler that runs the `run_maintenance()` function for you so that you don't have to use an external scheduler (cron, etc). Right now it doesn't do anything differently than calling `run_maintenance()` directly, but that may change in the future. See the README.md file for installation instructions. If you need to call `run_maintenance()` directly on any specific partition sets, you will still need to do so manually using an outside scheduler. This only maintains partition sets that have `automatic_maintenance` in `**part_config**` set to true. LOG messages are output to the normal PostgreSQL log file to indicate when the BGW runs. Additional logging messages are available if *log_min_messages* is set to "DEBUG1".

**REMEMBER:** You must have `pg_partman_bgw` in your `shared_preload_libraries` (requires a restart).

The following configuration options are available to add into postgresql.conf to control the BGW process:

 - `pg_partman_bgw.dbname`
    - Required. The database(s) that `run_maintenance()` will run on. If more than one, use a comma separated list. If not set, BGW will do nothing.
 - `pg_partman_bgw.interval`
    - Number of seconds between calls to `run_maintenance()`. Default is 3600 (1 hour).
    - See further documentation below on suggested values for this based on partition types & intervals used.
 - `pg_partman_bgw.role`
    - The role that `run_maintenance()` will run as. Default is "postgres". Only a single role name is allowed.
 - `pg_partman_bgw.analyze`
    - Same purpose as the p_analyze argument to `run_maintenance()`. See below for more detail. Set to 'on' for TRUE. Set to 'off' for FALSE (Default is 'off').
 - `pg_partman_bgw.jobmon`
    - Same purpose as the p_jobmon argument to `run_maintenance()`. See below for more detail. Set to 'on' for TRUE. Set to 'off' for FALSE. Default is 'on'.

If for some reason the main background worker process crashes, it is set to try and restart every 10 minutes. Check the postgres logs for any issues if the background worker is not starting.

Extension Objects
-----------------
Requiring a superuser to use pg_partman is completely optional. To run as a non-superuser, the role(s) that run pg_partman functions and maintenance must have ownership of all partition sets they manage and permissions to create objects in any schema that will contain partition sets that it manages. For ease of use and privilege management, it is recommended to create a role dedicated to partition management. Please see the main README.md file for role & privileges setup instructions.

As a note for people that were not aware, you can name arguments in function calls to make calling them easier and avoid confusion when there are many possible arguments. If a value has a default listed, it is not required to pass a value for that argument. As an example: `SELECT create_parent('schema.table', 'col1',  '1 day', p_start_partition := '2023-03-20');`

### Creation Functions

```sql
create_parent(
    p_parent_table text
    , p_control text
    , p_interval text
    , p_type text DEFAULT 'range'
    , p_epoch text DEFAULT 'none'
    , p_premake int DEFAULT 4
    , p_start_partition text DEFAULT NULL
    , p_default_table boolean DEFAULT true
    , p_automatic_maintenance text DEFAULT 'on'
    , p_constraint_cols text[] DEFAULT NULL
    , p_template_table text DEFAULT NULL
    , p_jobmon boolean DEFAULT true
    , p_date_trunc_interval text DEFAULT NULL
)
RETURNS boolean
```

 * Main function to create a partition set with one parent table and inherited children. Parent table must already exist and be declared as partitioned before calling this function. All options passed to this function must match that definition. Please apply all defaults, indexes, constraints, privileges & ownership to parent table so they will propagate to children. See notes above about handling unique indexes and other table properties.
 * An ACCESS EXCLUSIVE lock is taken on the parent table during the running of this function. No data is moved when running this function, so lock should be brief
 * A default partition and template table are created by default unless otherwise configured
 * `p_parent_table` - the existing parent table. MUST be schema qualified, even if in public schema
 * `p_control` - the column that the partitioning will be based on. Must be a time or integer based column
 * `p_interval` - the time or integer range interval for each partition. No matter the partitioning type, value must be given as text.
    + *\<interval\>*      - Any valid value for the interval data type. Do not type cast the parameter value, just leave as text.
    + *\<integer\>*       - For ID based partitions, the integer value range of the ID that should be set per partition. Enter this as an integer in text format ('100' not 100). Currently must be greater than or equal to 2.
 * `p_type` - the type of partitioning to be done. Currently only **range** is supported.
 * `p_epoch` - tells `pg_partman` that the control column is an integer type, but actually represents and epoch time value. Valid values for this option are: 'seconds', 'milliseconds', 'nanoseconds', and 'none'. The default is 'none'. All table names will be time-based. In addition to a normal index on the control column, be sure you create a functional, time-based index on the control column (to_timestamp(controlcolumn)) as well so this works efficiently.
 * `p_premake` - is how many additional partitions to always stay ahead of the current partition. Default value is 4. This will keep at minimum 5 partitions made, including the current one. For example, if today was Sept 6th, and `premake` was set to 4 for a daily partition, then partitions would be made for the 6th as well as the 7th, 8th, 9th and 10th. Note some intervals may occasionally cause an extra partition to be premade or one to be missed due to leap years, differing month lengths, etc. This usually won't hurt anything and should self-correct (see **About** section concerning timezones and non-UTC). If partitioning ever falls behind the `premake` value, normal running of `run_maintenance()` and data insertion should automatically catch things up.
 * `p_start_partition` - allows the first partition of a set to be specified instead of it being automatically determined. Must be a valid timestamp (for time-based) or positive integer (for id-based) value. Be aware, though, the actual parameter data type is text. For time-based partitioning, all partitions starting with the given timestamp up to CURRENT_TIMESTAMP (plus `premake`) will be created. For id-based partitioning, only the partition starting at the given value (plus `premake`) will be made. Note that for subpartitioning, this only applies during initial setup and not during ongoing maintenance.
 * `p_default_table` - boolean flag to determine whether a default table is created. Defaults to true.
 * `p_automatic_maintenance` - parameter to set whether maintenance is managed automatically when `run_maintenance()` is called without a table parameter or by the background worker process. Current valid values are "on" and "off". Default is "on". When set to off, `run_maintenance()` can still be called on an individual partition set by passing it as a parameter to the function.  See **run_maintenance** in Maintenance Functions section below for more info.
 * `p_constraint_cols` - an optional array parameter to set the columns that will have additional constraints set. See the **About** section above for more information on how this works and the **apply_constraints()** function for how this is used.
 * `p_template_table` - If you do not pass a value here, a template table will automatically be made for you in same schema that pg_partman was installed to. If you pre-create a template table and pass its name here, then the initial child tables will obtain these properties discussed in the **About** section immediately.
 * `p_jobmon` - allow `pg_partman` to use the `pg_jobmon` extension to monitor that partitioning is working correctly. Defaults to TRUE.
 * `p_date_trunc_interval` - By default, pg_partman's time-based partitioning will truncate the child table starting values to line up at the beginning of typical boundaries (midnight for daily, day 1 for monthly, Jan 1 for yearly, etc). If a custom time interval that does not fall on those boundaries is desired, this option may be required to ensure the child table has the expected boundaries (especially if you also set p_start_partition). The valid values allowed for this parameter are the interval values accepted by the built-in date_trunc() function (day, week, month, etc). For example, if you set a 9-week interval, by default pg_partman would truncate the tables by month (since the interval is greater than one month but less than 1 year) and unexpectedly start on the first of the month in some cases. Set this value to week, so that the child table start values are properly truncated on a weekly basis to line up with the 9-week interval. If you are using a custom time interval, please experiment with this option to get the expected set of child tables you desire or use a more typical partitioning interval to simplify partition management.

```sql
create_sub_parent(
    p_top_parent text
    , p_declarative_check text DEFAULT NULL
    , p_control text
    , p_interval text
    , p_type text DEFAULT 'range'
    , p_epoch text DEFAULT 'none'
    , p_premake int DEFAULT 4
    , p_start_partition text DEFAULT NULL
    , p_default_table boolean DEFAULT true
    , p_constraint_cols text[] DEFAULT NULL
    , p_jobmon boolean DEFAULT true
    , p_date_trunc_interval text DEFAULT NULL
)
RETURNS boolean
```

 * Create a subpartition set of an already existing partitioned set. See important notes about Subpartitioning in **About** section.
 * `p_top_parent` - This parameter is the parent table of an already existing partition set. It tells `pg_partman` to turn all child tables of the given partition set into their own parent tables of their own partition sets using the rest of the parameters for this function.
 * `p_declarative_check` - Turning an existing partition set into a subpartitioned set is a **destructive** process. A table must be declared partitioned at creation time and cannot be altered later. Therefore existing child tables must be dropped and recreated as partitioned parent tables. This flag is here to help ensure this function is not run without prior consent that all data in the partition set will be destroyed as part of the creation process. It must be set to "yes" to proceed with subpartitioning.
 * All other parameters to this function have the same exact purpose as those of `create_parent()`, but instead are used to tell `pg_partman` how each child table shall itself be partitioned.
 * For example if you have an existing partition set done by year and you then want to partition each of the year partitions by day, you would use this function.
 * It is advised that you keep table names short for subpartition sets if you plan on relying on the table names for organization. The suffix added on to the end of a table name is always guaranteed to be there for whatever partition type is active for that set. Longer table names may cause the original parent table names to be truncated and possibly cut off the top level partitioning suffix. This cannot be controlled and ensures the lowest level partitioning suffix survives.
 * Note that for the first level of subpartitions, the `p_parent_table` argument you originally gave to `create_parent()` would be the exact same value you give to `create_sub_parent()`. If you need further subpartitioning, you would then start giving `create_sub_parent()` a different value (the child tables of the top level partition set).
 * The template table that is already set for the given p_top_parent will automatically be used.


```sql
partition_data_time(
        p_parent_table text
        , p_batch_count int DEFAULT 1
        , p_batch_interval interval DEFAULT NULL
        , p_lock_wait numeric DEFAULT 0
        , p_order text DEFAULT 'ASC'
        , p_analyze boolean DEFAULT true
        , p_source_table text DEFAULT NULL
        , p_ignored_columns text[] DEFAULT NULL
)
RETURNS bigint
```

 * This function is used to partition data that may have existed prior to setting up the parent table as a time-based partition set. It also fixes data that gets inserted into the default table.
 * If the needed partition does not exist, it will automatically be created. If the needed partition already exists, the data will be moved there.
 * If you are trying to partition a large amount of data automatically, it is recommended to use the `partition_data_proc` procedure to commit data in smaller batches.  This will greatly reduce issues caused by long running transactions and data contention.
 * For subpartitioned sets, you must start partitioning data at the highest level and work your way down each level. This means you must first run this function before running create_sub_parent() to create the additional partitioning levels. Then continue running this function again on each new sub-parent once they're created. See the  pg_partman_howto.md document for a full example. IMPORTANT NOTE: Be VERY cautious with subpartition sets and using this function since subpartitioning can be a destructive operation. See create_sub_parent().
 * `p_parent_table` - the existing parent table. MUST be schema qualified, even if in public schema.
 * `p_batch_count` - optional argument, how many times to run the `batch_interval` in a single call of this function. Default value is 1. Currently sets how many child tables will be processed in a single run, but when p_batch_interval is working again will refer explicitly to how many batches to run.
 * `p_batch_interval` - optional argument, sets the interval of data to be moved in each batch. Defaults to the configured partition interval if not given or if you give an interval larger than the partition interval. IMPORTANT NOTE: This cannot be set smaller than the partition interval if moving data out of the default table. Work is being done to allow this, but with some limitations. If you are moving data from a source table that is not the partition set's default table, you can set this interval smaller than the partitioning interval to help avoid moving large amounts of data in long running transactions.
 * `p_lock_wait` - optional argument, sets how long in seconds to wait for a row to be unlocked before timing out. Default is to wait forever.
 * `p_order` - optional argument, by default data is migrated out of the default in ascending order (ASC). Allows you to change to descending order (DESC).
 * `p_analyze` - optional argument, by default whenever a new child table is created, an analyze is run on the parent table of the partition set to ensure constraint exclusion works. This analyze can be skipped by setting this to false and help increase the speed of moving large amounts of data. If this is set to false, it is highly recommended that a manual analyze of the partition set be done upon completion to ensure statistics are updated properly.
 * `p_source_table` - This option can be used when you need to move data into a partitioned table. Pass a schema qualified tablename to this parameter and any data in that table will be MOVED to the partition set designated by p_parent_table, creating any child tables as needed.
 * `p_ignored_columns` - This option allows for filtering out specific columns when moving data from the default/source to the target child table(s). This is generally only required when using columns with a GENERATED ALWAYS value since directly inserting a value would fail when moving the data. Value is a text array of column names.
 * Returns the number of rows that were moved from the parent table to partitions. Returns zero when source table is empty and partitioning is complete.


```sql
partition_data_id(p_parent_table text
    , p_batch_count int DEFAULT 1
    , p_batch_interval bigint DEFAULT NULL
    , p_lock_wait numeric DEFAULT 0
    , p_order text DEFAULT 'ASC'
    , p_analyze boolean DEFAULT true
    , p_source_table text DEFAULT NULL
    , p_ignored_columns text[] DEFAULT NULL
)
RETURNS bigint
```

 * This function is used to partition data that may have existed prior to setting up the parent table as a number-based partition set. It also fixes data that gets inserted into the default.
 * If the needed partition does not exist, it will automatically be created. If the needed partition already exists, the data will be moved there.
 * If you are trying to partition a large amount of data automatically, it is recommended to use the `partition_data_proc` procedure to commit data in smaller batches.  This will greatly reduce issues caused by long running transactions and data contention.
 * For subpartitioned sets, you must start partitioning data at the highest level and work your way down each level. This means you must first run this function before running create_sub_parent() to create the additional partitioning levels. Then continue running this function again on each new sub-parent once they're created. See the  pg_partman_howto.md document for a full example. IMPORTANT NOTE: Be VERY cautious with subpartition sets and using this function since subpartitioning can be a destructive operation. See create_sub_parent().
 * `p_parent_table` - the existing parent table. MUST be schema qualified, even if in public schema.
 * `p_batch_count` - optional argument, how many times to run the `batch_interval` in a single call of this function. Default value is 1. This sets how many child tables will be processed in a single run.
 * `p_batch_interval` - optional argument, sets the interval of data to be moved in each batch. Defaults to the configured partition interval if not given or if you give an interval larger than the partition interval. IMPORTANT NOTE: This cannot be set smaller than the partition interval if moving data out of the default table. Work is being done to allow this, but with some limitations. If you are moving data from a source table that is not the partition set's default table, you can set this interval smaller than the partitioning interval to help avoid moving large amounts of data in long running transactions.
 * `p_lock_wait` - optional argument, sets how long in seconds to wait for a row to be unlocked before timing out. Default is to wait forever.
 * `p_order` - optional argument, by default data is migrated out of the parent in ascending order (ASC). Allows you to change to descending order (DESC).
 * `p_analyze` - optional argument, by default whenever a new child table is created, an analyze is run on the parent table of the partition set to ensure constraint exclusion works. This analyze can be skipped by setting this to false and help increase the speed of moving large amounts of data. If this is set to false, it is highly recommended that a manual analyze of the partition set be done upon completion to ensure statistics are updated properly.
 * `p_source_table` - This option can be used when you need to move data into a partitioned table. Pass a schema qualified tablename to this parameter and any data in that table will be MOVED to the partition set designated by p_parent_table, creating any child tables as needed.
 * `p_ignored_columns` - This option allows for filtering out specific columns when moving data from the default/source to the target child table(s). This is generally only required when using columns with a GENERATED ALWAYS value since directly inserting a value would fail when moving the data. Value is a text array of column names.
 * Returns the number of rows that were moved from the parent table to partitions. Returns zero when source table is empty and partitioning is complete.


```sql
partition_data_proc (
    p_parent_table text
    , p_loop_count int DEFAULT NULL
    , p_interval text DEFAULT NULL
    , p_lock_wait int DEFAULT 0
    , p_lock_wait_tries int DEFAULT 10
    , p_wait int DEFAULT 1, p_order text DEFAULT 'ASC'
    , p_order text DEFAULT 'ASC',
    , p_source_table text DEFAULT NULL
    , p_ignored_columns text[] DEFAULT NULL
    , p_quiet boolean DEFAULT false
)
```

 * A procedure that can partition data in distinct commit batches to avoid long running transactions and data contention issues.
 * Calls either partition_data_time() or partition_data_id() in a loop depending on partitioning type.
 * `p_parent_table` - Parent table of an already created partition set.
 * `p_loop_count` - How many times to loop through the value given for p_interval. If p_interval not set, will use default partition interval and make at most this many partition(s). Procedure commits at the end of each loop (NOT passed as p_batch_count to partitioning function). If not set, all data in the parent/source table will be partitioned in a single run of the procedure.
 * `p_interval` - Parameter that is passed on to the partitioning function as p_batch_interval argument. See underlying functions for further explanation.
 * `p_lock_wait` - Parameter that is passed directly through to the underlying partition_data_*() function. Number of seconds to wait on rows that may be locked by another transaction. Default is to wait forever (0).
 * `p_lock_wait_tries` - Parameter to set how many times the procedure will attempt waiting the amount of time set for p_lock_wait. Default is 10 tries.
 * `p_wait` - Cause the procedure to pause for a given number of seconds between commits (batches) to reduce write load
 * `p_order` -  Same as the p_order option in the called partitioning function
 * `p_source_table` - Same as the p_source_table option in the called partitioning function
 * `p_ignored_columns` - This option allows for filtering out specific columns when moving data from the default/parent to the proper child table(s). This is generally only required when using columns with a GENERATED ALWAYS value since directly inserting a value would fail when moving the data. Value is a text array of column names.
 * `p_quiet` - Procedures cannot return values, so by default it emits NOTICE's to show progress. Set this option to silence these notices.


```sql
create_partition_time(
    p_parent_table text
    , p_partition_times timestamptz[]
    , p_start_partition text DEFAULT NULL
)
RETURNS boolean
```

 * This function is used to create child partitions for the given parent table.
 * Normally this function is never called manually since partition creation is managed by run_maintenance(). But if you need to force the creation of specific child tables outside of normal maintenance, this function makes it easier.
 * `p_parent_table` - parent table to create new child table(s) in.
 * `p_partition_times` - An array of timestamptz values to create children for. If the child table does not exist, it will be created. If it does exist, that one will be used and the function will still exit cleanly. Be aware that the value given will be used as the lower boundary for the child table and also influence the name given to the child table. So ensure the timestamp value given is consistent with other children or you may encounter a gap in value coverage.
 * `p_start_partition` - When using subpartitioning, allows passing along the start partition value for the subpartition child tables.
 * Returns TRUE if any child tables were created for the given timestamptz values. Returns false if no child tables were created.


```sql
create_partition_id(
    p_parent_table text
    , p_partition_ids bigint[]
    , p_start_partition text DEFAULT NULL
)
RETURNS boolean
```

 * This function is used to create child partitions for the given parent table.
 * Normally this function is never called manually since partition creation is managed by run_maintenance(). But if you need to force the creation of specific child tables outside of normal maintenance, this function can make it easier.
 * `p_parent_table` - parent table to create new child table(s) in.
 * `p_partition_ids` - An array of integer values to create children for. If the child table does not exist, it will be created. If it does exist, that one will be used and the function will still exit cleanly. Be aware that the value given will be used as the lower boundary for the child table and also influence the name given to the child table. So ensure the integer value given is consistent with other children or you may encounter a gap in value coverage.
 * `p_start_partition` - When using subpartitioning, allows passing along the start partition value for the subpartition child tables.
 * Returns TRUE if any child tables were created for the given integer values. Returns false if no child tables were created.


### Maintenance Functions

```sql
run_maintenance(
    p_parent_table text DEFAULT NULL
    , p_analyze boolean DEFAULT false
    , p_jobmon boolean DEFAULT true
)
RETURNS void
```

 * Run this function as a scheduled job (cron, etc) to automatically create child tables for partition sets configured to use it.
 * You can also use the included background worker (BGW) to have this automatically run for you by PostgreSQL itself. Note that the `p_parent_table` parameter is not available with this method, so if you need to run it for a specific partition set, you must do that manually or scheduled externally. The other parameters have postgresql.conf values that can be set. See BGW section earlier in this documentation.
 * This function also maintains the partition retention system for any partitions sets that have it turned on (see **About** and part_config table below).
 * Every run checks for all tables listed in the **part_config** table with **automatic_maintenance** set to true and either creates new partitions for them or runs their retention policy.
 * By default, all partition sets have automatic_maintenance set to true.
 * New partitions are only created if the number of child tables ahead of the current one is less than the premake value, so you can run this more often than needed without fear of needlessly creating more partitions.
 * `p_parent_table` - an optional parameter that if passed will cause `run_maintenance()` to be run for ONLY that given table, no matter what automatic_maintenance is set to. High transcation rate tables can cause contention when maintenance is being run for many tables at the same time, so this allows finer control of when partition maintenance is run for specific tables. Note that this will also cause the retention system to only be run for the given table as well.
 * `p_analyze` - By default, an analyze is not run after new child tables are created For large partition sets, an analyze can take a while and if `run_maintenance()` is managing several partitions in a single run, this can cause contention while the analyze finishes. However, for constraint exclusion or partition prunning to be fully effective, an analyze must be done from the parent level at some point. Set this to true to have an analyze run on any partition sets that have at least one new child table created. If no new child tables are created in a partition set, no analyze will be run even if this is set to true.
 * `p_jobmon` - an optional parameter to control whether `run_maintenance()` itself uses the `pg_jobmon` extension to log what it does. Whether the maintenance of a particular table uses `pg_jobmon` is controlled by the setting in the **part_config** table and this setting will have no affect on that. Defaults to true if not set.


```sql
run_maintenance_proc(
    p_wait int DEFAULT 0
    , p_analyze boolean DEFAULT NULL
    , p_jobmon boolean DEFAULT true
)
```

 * This procedure can be called instead of the `run_maintenance()` function to cause PostgreSQL to commit after each partition set's maintenance has finished. This greatly reduces contention issues with long running transactions when there are many partition sets to maintain.
 * NOTE: The BGW does not yet use this procedure and still uses the standard run_maintenance() function.
 * `p_wait` - How many seconds to wait between each partition set's maintenance run. Defaults to 0.
 * `p_analyze` - See p_analyze option in run_maintenance.


```sql
check_default(
    p_exact_count boolean DEFAULT true
)
```

 * Run this function to monitor if the default tables of the partition sets that `pg_partman` manages get rows inserted to them.
 * Returns a row for each parent/default table along with the number of rows it contains. Returns zero rows if none found.
 * `partition_data_time()` & `partition_data_id()` can be used to move data from these parent/default tables into the proper children.
 * p_exact_count will tell the function to give back an exact count of how many rows are in each parent if any is found. This is the default if the parameter is left out. If you don't care about an exact count, you can set this to false and it will return if it finds even just a single row in any parent. This can significantly speed up the check if a lot of data ends up in a parent or there are many partitions being managed.


```sql
show_partitions (
    p_parent_table text
    , p_order text DEFAULT 'ASC'
    , p_include_default boolean DEFAULT false
)
RETURNS TABLE (
    partition_schemaname text
    , partition_tablename text
)
```

 * List all child tables of a given partition set managed by pg_partman. Each child table returned as a single row.
 * Tables are returned in the order that logically makes sense for the partition interval, not by the locale ordering of their names.
 * The default partition can be returned in this result set as well if `p_include_default` is set to true. It is false by default since that is far more common with internal code.
 * `p_order` - optional parameter to set the order the child tables are returned in. Defaults to ASCending. Set to 'DESC' to return in descending order. If the default is included, it is always listed first.


```sql
show_partition_name(
    p_parent_table text
    , p_value text
    , OUT partition_schema text
    , OUT partition_table text
    , OUT suffix_timestamp timestamptz
    , OUT suffix_id bigint
    , OUT table_exists boolean
)
RETURNS record
```

 * Given a schema-qualified parent table managed by pg_partman (p_parent_table) and an appropriate value (time or id but given in text form for p_value), return the name of the child partition that that value would exist in.
 * If using epoch time partitioning, give the timestamp value, NOT the integer epoch value (use to_timestamp() to convert an epoch value).
 * Returns a child table name whether the child table actually exists or not
 * Also returns a raw value (suffix_timestamp or suffix_id) for the partition suffix for the given child table
 * Also returns a boolean value (table_exists) to say whether that child table actually exists


```sql
show_partition_info(p_child_table text
    , p_partition_interval text DEFAULT NULL
    , p_parent_table text DEFAULT NULL
    , OUT child_start_time timestamptz
    , OUT child_end_time timestamptz
    , OUT child_start_id bigint
    , OUT child_end_id bigint
    , OUT suffix text
)
RETURNS record
```

  * Given a schema-qualified child table name (p_child_table), return the relevant boundary values of that child as well as the suffix appended to the child table name.
  * Only works for existing child tables since the boundary values are calculated based on system catalogs of that table.
  * `p_partition_interval` - If given, return boundary results based on this interval. If not given, function looks up the interval stored in the part_config table for this partition set.
  * `p_parent_table` - Optional argument that can be given when parent_table is known and to avoid a catalog lookup for the parent table associated with p_child_table. Minor performance tuning tweak since this function is used a lot internally.
  * `OUT child_start_times & child_end_time` - Function returns values for these output parameters if the partition set is time-based. Otherwise outputs NULL. Note that start value is INCLUSIVE and end value is EXCLUSIVE of the given child table boundaries, exactly as they are defined in the database.
  * `OUT child_start_id & child_end_id` - Function returns values for these output parameters if the partition set is integer-based. Otherwise outputs NULL. Note that start value is INCLUSIVE and end value is EXCLUSIVE of the given child table boundaries, exactly as they are defined in the database.
  * `OUT suffix` - Outputs the text portition appended to the child table that identifies its contents minus the "_p" (Ex "20230324" OR "920000"). Useful for generating your own suffixes for partitioning similar to how pg_partman does it.


```sql
dump_partitioned_table_definition(
  p_parent_table text,
  p_ignore_template_table boolean DEFAULT false
)
RETURNS text
```

  * Function to return the necessary commands to recreate a partition set in pg_partman for the given parent table (p_parent_table).
  * Returns both the `create_parent()` call as well as an UPDATE statement to set additional parameters stored in part_config.
  * NOTE: This currently only works with single level partition sets. Looking for contributions to add support for subpartition sets
  * `p_ignore_template` - The template table needs to be created before the SQL generated by this function will work properly. If you haven't modified the template table at all then it's safe to pass TRUE here to have the generated SQL tell partman to generate a new template table. But for safety it's preferred to use pg_dump to dump the template tables and restore them prior to using the generated SQL so that you can maintain any template overrides.


```sql
partition_gap_fill(
    p_parent_table text
)
RETURNS integer
```

  * Function to fill in any gaps that may exist in the series of child tables for a given parent table (p_parent_table).
  * Starts from current minimum child table and fills in any gaps encountered based on the partition interval, up to the current maximum child table
  * Returns how many child tables are created. Returns 0 if none are created.


```sql
apply_constraints(
    p_parent_table text
    , p_child_table text DEFAULT NULL
    , p_analyze boolean DEFAULT FALSE
    , p_job_id bigint DEFAULT NULL
)
RETURNS void
```

 * Apply constraints to child tables in a given partition set for the columns that are configured (constraint names are all prefixed with "partmanconstr_").
 * Note that this does not need to be called manually to maintain custom constraints. The creation of new partitions automatically manages adding constraints to old child tables.
 * Columns that are to have constraints are set in the **part_config** table **constraint_cols** array column or during creation with the parameter to `create_parent()`.
 * If the `pg_partman` constraints already exists on the child table, the function will cleanly skip over the ones that exist and not create duplicates.
 * If the column(s) given contain all NULL values, no constraint will be made.
 * If the child table parameter is given, only that child table will have constraints applied.
 * If the child table parameter is NOT given, constraints are placed on the last child table older than the `optimize_constraint` value. For example, if the optimize_constraint value is 30, then constraints will be placed on the child table that is 31 back from the current partition (as long as partition pre-creation has been kept up to date).
 * If you need to apply constraints to all older child tables, use the `reapply_constraints_proc` procedure. This method has options to make constraint application easier with as little impact on performance as possible.
 * The p_job_id parameter is optional. It's for internal use and allows job logging to be consolidated into the original job that called this function if applicable.


```sql
drop_constraints(
    p_parent_table text
    , p_child_table text
    , p_debug boolean DEFAULT false
)
RETURNS void
```

 * Drop constraints that have been created by `pg_partman` for the columns that are configured in *part_config*. This makes it easy to clean up constraints if old data needs to be edited and the constraints aren't allowing it.
 * Will only drop constraints that begin with `partmanconstr_*` for the given child table and configured columns.
 * If you need to drop constraints on all child tables, use the `reapply_constraints_proc` procedure. This has options to make constraint removal easier with as little impact on performance as possible.
 * The debug parameter will show you the constraint drop statement that was used.


```sql
reapply_constraints_proc(
    p_parent_table text
    , p_drop_constraints boolean DEFAULT false
    , p_apply_constraints boolean DEFAULT false
    , p_wait int DEFAULT 0
    , p_dryrun boolean DEFAULT false
)
```

 * Procedure to reapply the extra constraint(s) managed by pg_partman (see "Constraint Exclusion" section in "About" section above).
 * Calls `drop_constraints()` and/or `apply_constraint()` in a loop, committing after each object is either dropped or added. This helps to avoid long running transaction and contention when doing this on large partition sets.
 * Typical usage would be to drop constraints first, edit the data as needed, then apply constraints again.
 * `p_parent_table` - Parent table of an already created partition set.
 * `p_drop_constraints` - Drop all constraints managed by pg_partman. Drops constraints on all child tables including current & future tables.
 * `p_apply_constraints` - Apply constraints on configured columns to all child tables older than the optimize_constraint value.
 * `p_wait` - Wait the given number of seconds after a table has had its constraints dropped or applied before moving on to the next.
 * `p_dryrun` - Do not actually apply the drop/apply constraint commands when this procedure is run. Just outputs which tables the commands will be applied to as NOTICEs.


```sql
reapply_privileges(
    p_parent_table text
)
RETURNS void
```

 * This function is used to reapply ownership & grants on all child tables based on what the parent table has set.
 * Privileges that the parent table has will be granted to all child tables and privilges that the parent does not have will be revoked (with CASCADE).
 * Privilges that are checked for are SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, & TRIGGER.
 * Be aware that for large partition sets, this can be a very long running operation and is why it was made into a separate function to run independently. Only privileges that are different between the parent & child are applied, but it still has to do system catalog lookups and comparisons for every single child partition and all individual privileges on each.
 * `p_parent_table` - parent table of the partition set. Must be schema qualified and match a parent table name already configured in `pg_partman`.


```sql
stop_sub_partition(
    p_parent_table text
    , p_jobmon boolean DEFAULT true
)
RETURNS boolean
```

 * By default, if you undo a child table that is also partitioned, it will not stop additional sibling children of the parent partition set from being subpartitioned unless that parent is also undone. To handle this situation where you may not be removing the parent but don't want any additional subpartitioned children, this function can be used.
 * This function simply deletes the parent_table entry from the part_config_sub table. But this gives a predictable, programmatic way to do so and also provides jobmon logging for the operation.


### Destruction Functions

```sql
undo_partition(
    p_parent_table text
    , p_target_table text
    , p_loop_count int DEFAULT 1
    , p_batch_interval text DEFAULT NULL
    , p_keep_table boolean DEFAULT true
    , p_lock_wait numeric DEFAULT 0
    , p_ignored_columns text[] DEFAULT NULL
    , p_drop_cascade boolean DEFAULT false
    , OUT partitions_undone int
    , OUT rows_undone bigint)
RETURNS record
```

 * Undo a partition set created by `pg_partman`. This function MOVES the data from the child tables to the given target table.
 * If you are trying to un-partition a large amount of data automatically, it is recommended to use the `undo_partition_data()` procedure to do the same thing. This will greatly reduce issues caused by long running transactions and data contention.
 * When this function is run, the **`undo_in_progress`** column in the configuration table is set to true. This causes all partition creation and retention management to stop.
 * By default, partitions are not DROPPED, they are DETTACHed. This leave previous child tables as empty, independent tables.
 * Without setting either batch argument manually, each run of the function will move all the data from a single partition into the target.
 * Once all child tables have been uninherited/dropped, the configuration data is removed from `pg_partman` automatically.
 * For subpartitioned tables, you may have to start at the lowest level parent table and undo from there then work your way up.
 * `p_parent_table` - parent table of the partition set. Must be schema qualified and match a parent table name already configured in `pg_partman`.
 * `p_target_table` - A schema-qualified table to move the old partitioned table's data to. Required since a partition table cannot be converted into a non-partitioned table. Schema can be different from original table.
 * `p_loop_count` - an optional argument, this sets how many times to move the amount of data equal to the `p_batch_interval` argument (or default partition interval if not set) in a single run of the function. Defaults to 1.
 * `p_batch_interval` - optional argument. A time or id interval of how much of the data to move. This can be smaller than the partition interval, allowing for very large partitions to be broken up into smaller commit batches. Defaults to the configured partition interval if not given or if you give an interval larger than the partition interval. Note that the value must be given as text to this parameter.
 * `p_keep_table` - an optional argument, setting this to false will cause the old child table to be dropped instead of detached after all of its data has been moved. Note that it takes at least two batches to actually drop a table from the set.
 * `p_lock_wait` - optional argument, sets how long in seconds to wait for either the table or a row to be unlocked before timing out. Default is to wait forever.
 * `p_ignored_columns` - This option allows for filtering out specific columns when moving data from the child tables to the target table. This is generally only required when using columns with a GENERATED ALWAYS value since directly inserting a value would fail when moving the data. Value is a text array of column names.
 * `p_drop_cascade` - Allow undoing subpartition sets from parent tables higher in the inheritance tree. Only applies when `p_keep_tables` is set to false. Note this causes all child tables below a subpartition parent to be dropped when that parent is dropped.
 * Returns the number of partitions undone and the number of rows moved to the parent table. The partitions undone value returns -1 if a problem is encountered.


```sql
undo_partition_proc(
    p_parent_table text
    , p_target_table text DEFAULT NULL
    , p_loop_count int DEFAULT NULL
    , p_interval text DEFAULT NULL
    , p_keep_table boolean DEFAULT true
    , p_lock_wait int DEFAULT 0
    , p_lock_wait_tries int DEFAULT 10
    , p_wait int DEFAULT 1
    , p_ignored_columns text[] DEFAULT NULL
    , p_drop_cascade boolean DEFAULT false
    , p_quiet boolean DEFAULT false
)

```

 * A procedure that can un-partition data in distinct commit batches to avoid long running transactions and data contention issues.
 * Calls the undo_partition() function in a loop, committing as needed.
 * `p_parent_table` - Parent table of an already created partition set.
 * `p_target_table` - Same as the p_target_table option in the undo_partition() function.
 * `p_loop_count` - How many times to loop through the value given for p_interval. If p_interval not set, will use default partition interval and undo at most this many partition(s). Procedure commits at the end of each loop (NOT passed as p_batch_count to partitioning function). If not set, all data in the partition set will be moved in a single run of the procedure.
 * `p_interval` - Value that is passed on to the undo_partition function as p_batch_interval argument. Use this to set an interval smaller than the partition interval to commit data in smaller batches. Defaults to the partition interval if not given.
 * `p_keep_table` - Same as the p_keep_table option in the undo_partition() function.
 * `p_lock_wait` - Parameter passed directly through to the underlying undo_partition() function. Number of seconds to wait on rows that may be locked by another transaction. Default is to wait forever (0).
 * `p_lock_wait_tries` - Parameter to set how many times the procedure will attempt waiting the amount of time set for p_lock_wait. Default is 10 tries.
 * `p_wait` - Cause the procedure to pause for a given number of seconds between commits (batches) to reduce write load
 * `p_ignored_columns` - This option allows for filtering out specific columns when moving data from the child tables to the target table. This is generally only required when using columns with a GENERATED ALWAYS value since directly inserting a value would fail when moving the data. Value is a text array of column names.
 * `p_drop_cascade` - Allow undoing subpartition sets from parent tables higher in the inheritance tree. Only applies when `p_keep_tables` is set to false. Note this causes all child tables below a subpartition parent to be dropped when that parent is dropped.
 * `p_quiet` - Procedures cannot return values, so by default it emits NOTICE's to show progress. Set this option to silence these notices.



```sql
drop_partition_time(
    p_parent_table text
    , p_retention interval DEFAULT NULL
    , p_keep_table boolean DEFAULT NULL
    , p_keep_index boolean DEFAULT NULL
    , p_retention_schema text DEFAULT NULL
    , p_reference_timestamp timestamptz DEFAULT CURRENT_TIMESTAMP
)
RETURNS int
```

 * This function is used to drop child tables from a time-based partition set based on a retention policy. By default, the table is just uninherited and not actually dropped. For automatically dropping old tables, it is recommended to use the `run_maintenance()` function with retention configured instead of calling this directly.
 * `p_parent_table` - the existing parent table of a time-based partition set. MUST be schema qualified, even if in public schema.
 * `p_retention` - optional parameter to give a retention time interval and immediately drop tables containing only data older than the given interval. If you have a retention value set in the config table already, the function will use that, otherwise this will override it. If not, this parameter is required. See the **About** section above for more information on retention settings.
 * `p_keep_table` - optional parameter to tell partman whether to keep or drop the table in addition to uninheriting it. TRUE means the table will not actually be dropped; FALSE means the table will be dropped. This function will use the value configured in **part_config** if not explicitly set. This option is ignored if retention_schema is set.
 * `p_keep_index` - optional parameter to tell partman whether to keep or drop the indexes of the child table when it is uninherited. TRUE means the indexes will be kept; FALSE means all indexes will be dropped. This function will use the value configured in **part_config** if not explicitly set. This option is ignored if p_keep_table is set to FALSE.
 * `p_retention_schema` - optional parameter to tell partman to move a table to another schema instead of dropping it. Set this to the schema you want the table moved to. This function will use the value configured in **`part_config`** if not explicitly set. If this option is set, the retention `p_keep_table` parameter is ignored.
 * `p_reference_timestamp` - optional parameter to tell partman to use a different reference timestamp from which to determine which partitions should be affected, default value is `CURRENT_TIMESTAMP`.
 * Returns the number of partitions affected.


```sql
drop_partition_id(
    p_parent_table text
    , p_retention bigint DEFAULT NULL
    , p_keep_table boolean DEFAULT NULL
    , p_keep_index boolean DEFAULT NULL
    , p_retention_schema text DEFAULT NULL
)
RETURNS int
```

 * This function is used to drop child tables from an integer-based partition set based on a retention policy. By default, the table just uninherited and not actually dropped. For automatically dropping old tables, it is recommended to use the `run_maintenance()` function with retention configured instead of calling this directly.
 * `p_parent_table` - the existing parent table of a time-based partition set. MUST be schema qualified, even if in public schema.
 * `p_retention` - optional parameter to give a retention integer interval and immediately drop tables containing only data less than the current maximum id value minus the given retention value. If you have a retention value set in the config table already, the function will use that, otherwise this will override it. If not, this parameter is required. See the **About** section above for more information on retention settings.
 * `p_keep_table` - optional parameter to tell partman whether to keep or drop the table in addition to uninheriting it. TRUE means the table will not actually be dropped; FALSE means the table will be dropped. This function will use the value configured in **part_config** if not explicitly set. This option is ignored if retention_schema is set.
 * `p_keep_index` - optional parameter to tell partman whether to keep or drop the indexes of the child table when it is uninherited. TRUE means the indexes will be kept; FALSE means all indexes will be dropped. This function will use the value configured in **part_config** if not explicitly set. This option is ignored if p_keep_table is set to FALSE.
 * `p_retention_schema` - optional parameter to tell partman to move a table to another schema instead of dropping it. Set this to the schema you want the table moved to. This function will use the value configured in **`part_config`** if not explicitly set. If this option is set, the retention `p_keep_table` parameter is ignored.
 * Returns the number of partitions affected.


### Tables

**`part_config`**

Stores all configuration data for partition sets mananged by the extension.

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


 - `parent_table`
    - Parent table of the partition set
 - `control`
    - Column used as the control for partition constraints. Must be a time or integer based column.
 - `partition_interval`
    - Text type value that determines the interval for each partition.
    - Must be a value that can either be cast to the interval or bigint data types.
 - `partition_type`
    - Type of partitioning. Must be one of the types mentioned above in the `create_parent()` info.
 - `premake`
    - How many partitions to keep pre-made ahead of the current partition. Default is 4.
 - `automatic_maintenance`
    - Flag to set whether maintenance is managed automatically when `run_maintenance()` is called without a table parameter or by the background worker process.
    - Current valid values are "on" and "off". Default is "on".
    - When set to off, `run_maintenance()` can still be called on in individual partition set by passing it as a parameter to the function.
 - `template_table`
    - The schema-qualified name of the table used as a template for applying any inheritance options not handled by core PostgreSQL partitioning options in PG.
 - `retention`
    - Text type value that determines how old the data in a child partition can be before it is dropped.
    - Must be a value that can either be cast to the interval (for time-based partitioning) or bigint (for number partitioning) data types.
    - Leave this column NULL (the default) to always keep all child partitions. See **About** section for more info.
 - `retention_schema`
    - Schema to move tables to as part of the retentions system instead of dropping them. Overrides retention_keep_table option.
 - `retention_keep_index`
    - Boolean value to determine whether indexes are dropped for child tables that are detached.
    - Default is TRUE. Set to FALSE to have the child table's indexes dropped when it is detached.
 - `retention_keep_table`
    - Boolean value to determine whether dropped child tables only detached or actually dropped.
    - Default is TRUE to keep the table and only uninherit it. Set to FALSE to have the child tables removed from the database completely.
 - `epoch`
    - Flag the table to be partitioned by time by an integer epoch value instead of a timestamp. See `create_parent()` function for more info. Default 'none'.
 - `constraint_cols`
    - Array column that lists columns to have additional constraints applied. See **About** section for more information on how this feature works.
 - `optimize_constraint`
    - Manages which old tables get additional constraints set if configured to do so. See **About** section for more info. Default 30.
 - `infinite_time_partitions`
    - By default, new partitions in a time-based set will not be created if new data is not inserted to keep an infinite amount of empty tables from being created.
    - If you'd still like new partitions to be made despite there being no new data, set this to TRUE.
    - Defaults to FALSE.
 - `datetime_string`
    - For time-based partitioning, this is the datetime format string used when naming child partitions.
 - `jobmon`
    - Boolean value to determine whether the `pg_jobmon` extension is used to log/monitor partition maintenance. Defaults to true.
 - `sub_partition_set_full`
    - Boolean value to denote that the final partition for a subpartition set has been created. Allows run_maintenance() to run more efficiently when there are large numbers of subpartition sets.
 - `undo_in_progress`
    - Set by the undo_partition functions whenever they are run. If true, this causes all partition creation and retention management by the `run_maintenance()` function to stop. Default is false.
 - `inherit_privileges`
    - Sets whether to inherit the ownership/privileges of the parent table to all child tables. Defaults to false and should only be necessary if you need direct access to child tables, by-passing the parent table.
  - `constraint_valid`
    - Boolean value that allows the additional constraints that pg_partman can manage for you to be created as NOT VALID. See "Constraint Exclusion" section at the beginning for more details on these constraints. This can allow maintenance to run much quicker on large partition sets since the existing data is not validated before additing the constraint. Newly inserted data is validated, so this is a perfectly safe option to set for data integrity. Note that constraint exclusion WILL NOT work until the constraints are validated. Defaults to true so that constraints are created as VALID. Set to false to set new constraints as NOT VALID.
  - `subscription_refresh` - Name of a logical replication subscription to refresh when maintenance runs. If the partition set is subscribed to a publication that will be adding/removing tables and you need your partition set to be aware of these changes, you must name that subscription with this option. Otherwise the subscription will never become aware of the new tables added to the publisher unless you are refreshing the subscription via some other means. See the PG documentation for ALTER SUBSCRIPTION for more info on refreshing subscriptions - https://www.postgresql.org/docs/current/sql-altersubscription.html
 - `ignore_default_data` - By default, maintenance will ignore data in the default table when determining whether a new child table should be made. This means that if data is in the default and new child table would contain that data, an error will be thrown. If you need maintenance to acknowledge data in the default to fix a maintenance issue, this can be set to false. Note this can cause gaps in child table coverage, which can made data going into the default even worse, so it should not be left enabled once maintenance issues have been fixed.

**`part_config_sub`**

 * Stores all configuration data for subpartitioned sets managed by `pg_partman`.
 * The **`sub_parent`** column is the parent table of the subpartition set and all other columns govern how that parent's children are subpartitioned.
 * All other columns work the same exact way as their counterparts in either the **`part_config`** table or as the parameters passed to `create_parent()`.


### Scripts

If the extension was installed using *make*, the below script files should have been installed to the PostgreSQL binary directory.

*`dump_partition.py`*

 * A python script to dump out tables contained in the given schema. Uses pg_dump, creates a SHA-512 hash file of the dump file, and then drops the table.
 * When combined with the retention_schema configuration option, provides a way to reliably dump out tables that would normally just be dropped by the retention system.
 * Tables are not dropped if pg_dump does not return successfully.
 * The connection options for psycopg and pg_dump were separated out due to distinct differences in their requirements depending on your database connection configuration.
 * All dump_* option defaults are the same as they would be for pg_dump if they are not given.
 * Will work on any given schema, not just the one used to manage `pg_partman` retention.
 * `--schema (-n)`:          The schema that contains the tables that will be dumped. (Required).
 * `--connection (-c)`:      Connection string for use by psycopg.
                             Role used must be able to select from pg_catalog.pg_tables in the relevant database and drop all tables in the given schema.
                             Defaults to "host=" (local socket). Note this is distinct from the parameters sent to pg_dump.
 * `--output (-o)`:          Path to dump file output location. Default is where the script is run from.
 * `--dump_database (-d)`:   Used for pg_dump, same as its --dbname option or final database name parameter.
 * `--dump_host`:            Used for pg_dump, same as its --host option.
 * `--dump_username`:        Used for pg_dump, same as its --username option.
 * `--dump_port`:            Used for pg_dump, same as its --port option.
 * `--pg_dump_path`:         Path to pg_dump binary location. Must set if not in current PATH.
 * `--Fp`:                   Dump using pg_dump plain text format. Default is binary custom (-Fc).
 * `--nohashfile`:           Do NOT create a separate file with the SHA-512 hash of the dump. If dump files are very large, hash generation can possibly take a long time.
 * `--nodrop`:               Do NOT drop the tables from the given schema after dumping/hashing.
 * `--verbose (-v)`:         Provide more verbose output.
 * `--version`:              Print out the minimum version of `pg_partman` this script is meant to work with. The version of `pg_partman` installed may be greater than this.


*`vacuum_maintenance.py`*

 * A python script to perform additional VACUUM maintenance on a given partition set. The main purpose of this is to provide an easier means of freezing tuples in older partitions that are no longer written to. This allows autovacuum to skip over them safely without causing transaction id wraparound issues. See the PostgreSQL documentation for more information on this maintenance issue: http://www.postgresql.org/docs/current/static/routine-vacuuming.html#VACUUM-FOR-WRAPAROUND.
 * Vacuums all child tables in a given partition set who's age(relfrozenxid) is greater than vacuum_freeze_min_age, including the parent table.
 * Highly recommend scheduled runs of this script with the --freeze option if you have child tables that never have writes after a certain period of time.
 * --parent (-p):               Parent table of an already created partition set.  (Required)
 * --connection (-c):           Connection string for use by psycopg. Defaults to "host=" (local socket).
 * --freeze (-z):               Sets the FREEZE option to the VACUUM command.
 * --full (-f):                 Sets the FULL option to the VACUUM command. Note that --freeze is not necessary if you set this. Recommend reviewing --dryrun before running this since it will lock all tables it runs against, possibly including the parent.
 * --vacuum_freeze_min_age (-a): By default the script obtains this value from the system catalogs. By setting this, you can override the value obtained from the database. Note this does not change the value in the database, only the value this script uses.
 * --noparent:                  Normally the parent table is included in the list of tables to vacuum if its age(relfrozenxid) is higher than vacuum_freeze_min_age. Set this to force exclusion of the parent table, even if it meets that criteria.
 * --dryrun:                    Show what the script will do without actually running it against the database. Highly recommend reviewing this before running for the first time.
 * --quiet (-q):                Turn off all output.
 * --debug:                     Show additional debugging output.


*`check_unique_constraints.py`*

 * Declarative partitioning has the shortcoming of not allowing a unique constraint if the constraint does not include the partition column. This is often not possible, especially with time-based partitioning. This script is used to check that all rows in a partition set are unique for the given columns.
 * Note that on very large partition sets this can be an expensive operation to run that can consume large amounts of storage space. The amount of storage space required is enough to dump out the entire index's column data as a plaintext file.
 * If there is a column value that violates the unique constraint, this script will return those column values along with a count of how many of each value there are. Output can also be simplified to a single, total integer value to make it easier to use with monitoring applications.
 * `--parent (-p)`:           Parent table of the partition set to be checked. (Required)
 * `--column_list (-l)`:      Comma separated list of columns that make up the unique constraint to be checked. (Required)
 * `--connection (-c)`:       Connection string for use by psycopg. Defaults to "host=" (local socket).
 * `--temp (-t)`:             Path to a writable folder that can be used for temp working files. Defaults system temp folder.
 * `--psql`:                  Full path to psql binary if not in current PATH.
 * `--simple`:                Output a single integer value with the total duplicate count. Use this for monitoring software that requires a simple value to be checked for.
 * `--quiet (-q)`:            Suppress all output unless there is a constraint violation found.
 * `--version`:               Print out the minimum version of `pg_partman` this script is meant to work with. The version of `pg_partman` installed may be greater than this.
