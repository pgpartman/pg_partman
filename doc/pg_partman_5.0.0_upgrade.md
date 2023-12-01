Guildelines for Upgrading to pg_partman 5.0.0
=============================================

IMPORTANT NOTE: This document assumes all partition sets are native partition sets. If you have trigger-based partitioning sets, you must migrate them to native first before doing any further work to make your partition set compatible with pg_partman 5.0.0 and greater.

## Deprecated Partitioning Methods
There are several partitioning schemes that pg_partman supported prior to version 5.0.0 that are no longer supported, namely ISO weekly and Quarterly. Note that is still possible to partition with these intervals in version 5 and above using the intervals "1 week" or "3 months". It's just the specialized versions of this partitioning that were done before are no longer supported.

Previously weekly partitioning could be done using the ISO week format `IYYYwIW` which would result in partitioning suffixes like 2021w44 or 1994w32 where the number after the `w` was the numbered week of that year and the year would always be sure to be aligned with an ISO week. Also supported was a quarterly partitioning method with the suffix `YYYYq#` where # was one of the 4 standard quarters in a year starting with January 1st. The quarterly method was particularly problematic to support since not all the time-based functions supported it properly.

So while quarterly was problematic to maintain, weekly did work well for the most part. But after reviewing the code to maintain all the different specialized suffixes (8 in total), it was decided to simplify the suffixes that would be supported. Now there are only two possibilities:

 * `YYYYMMDD` for intervals greater than or equal to 1 day
 * `YYYYMMDD_HH24MISS` for intervals less than 1 day (supported down to 1 second)

Custom interval support had always been possible with pg_partman, especially with native partitioning. But the simplification of the suffixes supported greatly simplifies the code maintenance. If you were using either of these partitioning methods, you will have to migrate away from them in order to use pg_partman 5.0.0 or greater. The migration can be done before or after the upgrade, but just note that partition maintenance will not work for these methods in 5+ and will generate errors when maintenance runs for these sets until after the migration.

Note that previously `hourly` partitioning did not have seconds in the suffix, but any new partition sets made with that interval will. There is no hard requirement to migrate like there is for weekly and quarterly, but there will be an inconsistency in child table naming with any existing partition sets from before 5.x. A migration similar to the below examples can be done if consistency is desired.

The migration is simply a renaming of the child tables and an update to the partman configuration table(s) so it should be a relatively smooth process with little downtime.

### Weekly Migration

Here is an example weekly partition set created with pg_partman version 4.7.3.
```sql
 \d+ partman_test.time_taptest_table
                                                       Partitioned table "partman_test.time_taptest_table"
 Column |           Type           | Collation | Nullable |                    Default                     | Storage  | Compression | Stats target | Description
--------+--------------------------+-----------+----------+------------------------------------------------+----------+-------------+--------------+-------------
 col1   | timestamp with time zone |           |          |                                                | plain    |             |              |
 col2   | text                     |           |          |                                                | extended |             |              |
 col3   | integer                  |           | not null | EXTRACT(epoch FROM CURRENT_TIMESTAMP)::integer | plain    |             |              |
Partition key: RANGE (col1)
Partitions: partman_test.time_taptest_table_p2023w05 FOR VALUES FROM ('2023-01-30 00:00:00-05') TO ('2023-02-06 00:00:00-05'),
            partman_test.time_taptest_table_p2023w06 FOR VALUES FROM ('2023-02-06 00:00:00-05') TO ('2023-02-13 00:00:00-05'),
            partman_test.time_taptest_table_p2023w07 FOR VALUES FROM ('2023-02-13 00:00:00-05') TO ('2023-02-20 00:00:00-05'),
            partman_test.time_taptest_table_p2023w08 FOR VALUES FROM ('2023-02-20 00:00:00-05') TO ('2023-02-27 00:00:00-05'),
            partman_test.time_taptest_table_p2023w09 FOR VALUES FROM ('2023-02-27 00:00:00-05') TO ('2023-03-06 00:00:00-05'),
            partman_test.time_taptest_table_p2023w10 FOR VALUES FROM ('2023-03-06 00:00:00-05') TO ('2023-03-13 00:00:00-04'),
            partman_test.time_taptest_table_p2023w11 FOR VALUES FROM ('2023-03-13 00:00:00-04') TO ('2023-03-20 00:00:00-04'),
            partman_test.time_taptest_table_p2023w12 FOR VALUES FROM ('2023-03-20 00:00:00-04') TO ('2023-03-27 00:00:00-04'),
            partman_test.time_taptest_table_p2023w13 FOR VALUES FROM ('2023-03-27 00:00:00-04') TO ('2023-04-03 00:00:00-04'),
            partman_test.time_taptest_table_p2023w14 FOR VALUES FROM ('2023-04-03 00:00:00-04') TO ('2023-04-10 00:00:00-04'),
            partman_test.time_taptest_table_p2023w15 FOR VALUES FROM ('2023-04-10 00:00:00-04') TO ('2023-04-17 00:00:00-04'),
            partman_test.time_taptest_table_p2023w16 FOR VALUES FROM ('2023-04-17 00:00:00-04') TO ('2023-04-24 00:00:00-04'),
            partman_test.time_taptest_table_p2023w17 FOR VALUES FROM ('2023-04-24 00:00:00-04') TO ('2023-05-01 00:00:00-04'),
            partman_test.time_taptest_table_default DEFAULT

```
The contents of the config table are as follows (note the columns in the config table have changed significantly in 5.x and greater)
```sql
SELECT * FROM partman.part_config;

-[ RECORD 1 ]--------------+-------------------------------------------------
parent_table               | partman_test.time_taptest_table
control                    | col1
partition_type             | native
partition_interval         | 7 days
constraint_cols            |
premake                    | 4
optimize_trigger           | 4
optimize_constraint        | 30
epoch                      | none
inherit_fk                 | t
retention                  |
retention_schema           |
retention_keep_table       | t
retention_keep_index       | t
infinite_time_partitions   | f
datetime_string            | IYYY"w"IW
automatic_maintenance      | on
jobmon                     | t
sub_partition_set_full     | f
undo_in_progress           | f
trigger_exception_handling | f
upsert                     |
trigger_return_null        | t
template_table             | partman.template_partman_test_time_taptest_table
publications               |
inherit_privileges         | f
constraint_valid           | t
subscription_refresh       |
drop_cascade_fk            | f
ignore_default_data        | f
```

We will use a query below to generate some SQL that will rename the tables to the new naming pattern supported in 5.x and greater. Adjustments to this query for your tables are

 * Replace the table name of the parent in this query with the name of yours
 * In the first substring function, the number after `for` should be the character length of your parent table name +2 to account for the `_p`. In this case `20`
 * In the second substring function, the number after the `from` should be the previous number +1. In this case `21`

```sql
SELECT format(
    'ALTER TABLE %I.%I RENAME TO %I;'
    , n.nspname
    , c.relname
    , substring(c.relname from 1 for 20) || to_char(to_timestamp(substring(c.relname from 21), 'IYYY"w"IW'), 'YYYYMMDD')
)
FROM pg_inherits h
JOIN pg_class c ON h.inhrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE h.inhparent::regclass = 'partman_test.time_taptest_table'::regclass
AND c.relname NOT LIKE '%_default'
ORDER BY c.relname;

                                           ?column?  
----------------------------------------------------------------------------------------------
 ALTER TABLE partman_test.time_taptest_table_p2023w05 RENAME TO time_taptest_table_p20230130;
 ALTER TABLE partman_test.time_taptest_table_p2023w06 RENAME TO time_taptest_table_p20230206;
 ALTER TABLE partman_test.time_taptest_table_p2023w07 RENAME TO time_taptest_table_p20230213;
 ALTER TABLE partman_test.time_taptest_table_p2023w08 RENAME TO time_taptest_table_p20230220;
 ALTER TABLE partman_test.time_taptest_table_p2023w09 RENAME TO time_taptest_table_p20230227;
 ALTER TABLE partman_test.time_taptest_table_p2023w10 RENAME TO time_taptest_table_p20230306;
 ALTER TABLE partman_test.time_taptest_table_p2023w11 RENAME TO time_taptest_table_p20230313;
 ALTER TABLE partman_test.time_taptest_table_p2023w12 RENAME TO time_taptest_table_p20230320;
 ALTER TABLE partman_test.time_taptest_table_p2023w13 RENAME TO time_taptest_table_p20230327;
 ALTER TABLE partman_test.time_taptest_table_p2023w14 RENAME TO time_taptest_table_p20230403;
 ALTER TABLE partman_test.time_taptest_table_p2023w15 RENAME TO time_taptest_table_p20230410;
 ALTER TABLE partman_test.time_taptest_table_p2023w16 RENAME TO time_taptest_table_p20230417;
 ALTER TABLE partman_test.time_taptest_table_p2023w17 RENAME TO time_taptest_table_p20230424;
```

Note that all ISO weeks start on Monday, so that is the first day of the week that the child table names will be based on. This also lines up with the original boundaries of the child tables if you look at them above, so child table names should be lining up with the lower boundaries of the data they contain. If you happened to want your weeks to start on a Sunday (or some other day), that would require a much more involved migration of the data itself as well, and is beyond the scope of this document.

Lastly you need to update the `datetime_string` column in the part_config table to the new suffix pattern.
```sql
UPDATE partman.part_config SET datetime_string = 'YYYYMMDD';
```
Now we can test if this is working by increasing the premake value. The default value of the premake is 4, so if you'd changed that previously, just add one to that value. We're also setting `infinite_time_partitions` to true here as well because there may not be enough data in the partition set yet to cause future tables to be created. This can be disabled again after testing here if that is not desired.
```sql
UPDATE partman.part_config SET premake = premake+1, infinite_time_partitions = true;
```
Now we can call run_maintenance() to ensure partition maintenance is working as expected
```sql
SELECT partman.run_maintenance('partman_test.time_taptest_table');
```
```sql
keith=# \d+ partman_test.time_taptest_table
                                                       Partitioned table "partman_test.time_taptest_table"
 Column |           Type           | Collation | Nullable |                    Default                     | Storage  | Compression | Stats target | Description
--------+--------------------------+-----------+----------+------------------------------------------------+----------+-------------+--------------+-------------
 col1   | timestamp with time zone |           |          |                                                | plain    |             |              |
 col2   | text                     |           |          |                                                | extended |             |              |
 col3   | integer                  |           | not null | EXTRACT(epoch FROM CURRENT_TIMESTAMP)::integer | plain    |             |              |
Partition key: RANGE (col1)
Partitions: partman_test.time_taptest_table_p20230130 FOR VALUES FROM ('2023-01-30 00:00:00-05') TO ('2023-02-06 00:00:00-05'),
            partman_test.time_taptest_table_p20230206 FOR VALUES FROM ('2023-02-06 00:00:00-05') TO ('2023-02-13 00:00:00-05'),
            partman_test.time_taptest_table_p20230213 FOR VALUES FROM ('2023-02-13 00:00:00-05') TO ('2023-02-20 00:00:00-05'),
            partman_test.time_taptest_table_p20230220 FOR VALUES FROM ('2023-02-20 00:00:00-05') TO ('2023-02-27 00:00:00-05'),
            partman_test.time_taptest_table_p20230227 FOR VALUES FROM ('2023-02-27 00:00:00-05') TO ('2023-03-06 00:00:00-05'),
            partman_test.time_taptest_table_p20230306 FOR VALUES FROM ('2023-03-06 00:00:00-05') TO ('2023-03-13 00:00:00-04'),
            partman_test.time_taptest_table_p20230313 FOR VALUES FROM ('2023-03-13 00:00:00-04') TO ('2023-03-20 00:00:00-04'),
            partman_test.time_taptest_table_p20230320 FOR VALUES FROM ('2023-03-20 00:00:00-04') TO ('2023-03-27 00:00:00-04'),
            partman_test.time_taptest_table_p20230327 FOR VALUES FROM ('2023-03-27 00:00:00-04') TO ('2023-04-03 00:00:00-04'),
            partman_test.time_taptest_table_p20230403 FOR VALUES FROM ('2023-04-03 00:00:00-04') TO ('2023-04-10 00:00:00-04'),
            partman_test.time_taptest_table_p20230410 FOR VALUES FROM ('2023-04-10 00:00:00-04') TO ('2023-04-17 00:00:00-04'),
            partman_test.time_taptest_table_p20230417 FOR VALUES FROM ('2023-04-17 00:00:00-04') TO ('2023-04-24 00:00:00-04'),
            partman_test.time_taptest_table_p20230424 FOR VALUES FROM ('2023-04-24 00:00:00-04') TO ('2023-05-01 00:00:00-04'),
            partman_test.time_taptest_table_p20230501 FOR VALUES FROM ('2023-05-01 00:00:00-04') TO ('2023-05-08 00:00:00-04'),
            partman_test.time_taptest_table_p20230508 FOR VALUES FROM ('2023-05-08 00:00:00-04') TO ('2023-05-15 00:00:00-04'),
            partman_test.time_taptest_table_default DEFAULT
```
You can see that maintenance has created new partitions with our new naming pattern without any issues. You may get one or more depending on the state of your child tables at the time this is run

If all is well, you can return your `premake` and `infinite_time_partitions` values back to their previous values if needed.

If you want to ensure any weekly partitioned tables start on a Monday when you create them, you can use the `date_trunc()` function in the `p_start_partition` parameter to `create_parent()` to do that. The following example shows doing this on a Tuesday. Without setting a specific starting partition like this, the partition set would have started on Tues, Aug 29 2023 and every future partition would have been based on a week starting on Tuesday.

```sql
SELECT CURRENT_TIMESTAMP;
       current_timestamp  
-------------------------------
 2023-08-29 13:22:08.190552-04


CREATE TABLE public.time_table (
    col1 int,
    col2 text,
    col3 timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP)
PARTITION BY RANGE (col3);


SELECT partman.create_parent('public.time_table', 'col3', '1 week', p_start_partition := to_char(date_trunc('week',CURRENT_TIMESTAMP), 'YYYY-MM-DD HH24:MI:SS'));
```
```sql
\d+ public.time_table
                                               Partitioned table "public.time_table"
 Column |           Type           | Collation | Nullable |      Default      | Storage  | Compression | Stats target | Description
--------+--------------------------+-----------+----------+-------------------+----------+-------------+--------------+-------------
 col1   | integer                  |           |          |                   | plain    |             |              |
 col2   | text                     |           |          |                   | extended |             |              |
 col3   | timestamp with time zone |           | not null | CURRENT_TIMESTAMP | plain    |             |              |
Partition key: RANGE (col3)
Partitions: time_table_p20230828 FOR VALUES FROM ('2023-08-28 00:00:00-04') TO ('2023-09-04 00:00:00-04'),
            time_table_p20230904 FOR VALUES FROM ('2023-09-04 00:00:00-04') TO ('2023-09-11 00:00:00-04'),
            time_table_p20230911 FOR VALUES FROM ('2023-09-11 00:00:00-04') TO ('2023-09-18 00:00:00-04'),
            time_table_p20230918 FOR VALUES FROM ('2023-09-18 00:00:00-04') TO ('2023-09-25 00:00:00-04'),
            time_table_p20230925 FOR VALUES FROM ('2023-09-25 00:00:00-04') TO ('2023-10-02 00:00:00-04'),
            time_table_default DEFAULT

```

### Quarterly Partitioning

Similar to weekly, the names of the child tables just need to be renamed and the partman config updated with the new datetime_string. Below is the table as it was with the original quarterly names
```sql
\d+ partman_test.time_taptest_table
                                   Partitioned table "partman_test.time_taptest_table"
 Column |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description
--------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 col1   | integer                  |           |          |         | plain    |             |              |
 col2   | text                     |           |          |         | extended |             |              |
 col3   | timestamp with time zone |           | not null | now()   | plain    |             |              |
Partition key: RANGE (col3)
Partitions: partman_test.time_taptest_table_p2022q1 FOR VALUES FROM ('2022-01-01 00:00:00-05') TO ('2022-04-01 00:00:00-04'),
            partman_test.time_taptest_table_p2022q2 FOR VALUES FROM ('2022-04-01 00:00:00-04') TO ('2022-07-01 00:00:00-04'),
            partman_test.time_taptest_table_p2022q3 FOR VALUES FROM ('2022-07-01 00:00:00-04') TO ('2022-10-01 00:00:00-04'),
            partman_test.time_taptest_table_p2022q4 FOR VALUES FROM ('2022-10-01 00:00:00-04') TO ('2023-01-01 00:00:00-05'),
            partman_test.time_taptest_table_p2023q1 FOR VALUES FROM ('2023-01-01 00:00:00-05') TO ('2023-04-01 00:00:00-04'),
            partman_test.time_taptest_table_p2023q2 FOR VALUES FROM ('2023-04-01 00:00:00-04') TO ('2023-07-01 00:00:00-04'),
            partman_test.time_taptest_table_p2023q3 FOR VALUES FROM ('2023-07-01 00:00:00-04') TO ('2023-10-01 00:00:00-04'),
            partman_test.time_taptest_table_p2023q4 FOR VALUES FROM ('2023-10-01 00:00:00-04') TO ('2024-01-01 00:00:00-05'),
            partman_test.time_taptest_table_p2024q1 FOR VALUES FROM ('2024-01-01 00:00:00-05') TO ('2024-04-01 00:00:00-04'),
            partman_test.time_taptest_table_default DEFAULT
```
Here is the SQL to generate the renames of the child tables. Note this is quite a bit more complicated because quarterly does not work as expected with the `to_timestamp()` function. We'll have to use an anonymous function to run some PL/PQSL code to generate the SQL for changing these table names.

Note you will have to adjust the substring in the generation of the ALTER TABLE statement to match the length of your parent table name +2 (to account for the `_p`). In this case the value is `20`.

```sql
DO $rename$
DECLARE
    v_child_start_time      timestamptz;
    v_row                   record;
    v_quarter               text;
    v_sql                   text;
    v_suffix                text;
    v_suffix_position       int;
    v_year                  text;
BEGIN

-- Adjust your parent table name in the for loop query
FOR v_row IN
    SELECT n.nspname AS child_schema, c.relname AS child_table
        FROM pg_inherits h
        JOIN pg_class c ON h.inhrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE h.inhparent = 'partman_test.time_taptest_table'::regclass
        AND c.relname NOT LIKE '%_default'
        ORDER BY c.relname
LOOP

    v_suffix_position := (length(v_row.child_table) - position('p_' in reverse(v_row.child_table))) + 2;
    v_suffix := substring(v_row.child_table from v_suffix_position);

    v_year := split_part(v_suffix, 'q', 1);
    v_quarter := split_part(v_suffix, 'q', 2);
    CASE
        WHEN v_quarter = '1' THEN
            v_child_start_time := to_timestamp(v_year || '-01-01', 'YYYY-MM-DD');
        WHEN v_quarter = '2' THEN
            v_child_start_time := to_timestamp(v_year || '-04-01', 'YYYY-MM-DD');
        WHEN v_quarter = '3' THEN
            v_child_start_time := to_timestamp(v_year || '-07-01', 'YYYY-MM-DD');
        WHEN v_quarter = '4' THEN
            v_child_start_time := to_timestamp(v_year || '-10-01', 'YYYY-MM-DD');
        ELSE
           RAISE EXCEPTION 'Unexpected code path';
    END CASE;

    -- Build the sql statement to rename the child table
    v_sql := format('ALTER TABLE %I.%I RENAME TO %I;'
            , v_row.child_schema
            , v_row.child_table
            , substring(v_row.child_table from 1 for 20)||to_char(v_child_start_time, 'YYYYMMDD'));

    RAISE NOTICE '%', v_sql;
END LOOP;

END
$rename$;
```
Then update the configuration to use the new datetime_string. Note this is the same as weekly now
```sql
UPDATE partman.part_config SET datetime_string = 'YYYYMMDD';
```
The remaining steps to test that things are working is the same as weekly
```sql
UPDATE partman.part_config SET premake = premake+1, infinite_time_partitions = true;

SELECT partman.run_maintenance('partman_test.time_taptest_table');
```
You should see at least one more additional child table now
```sql
\d+ partman_test.time_taptest_table
                                   Partitioned table "partman_test.time_taptest_table"
 Column |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description
--------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 col1   | integer                  |           |          |         | plain    |             |              |
 col2   | text                     |           |          |         | extended |             |              |
 col3   | timestamp with time zone |           | not null | now()   | plain    |             |              |
Partition key: RANGE (col3)
Partitions: partman_test.time_taptest_table_p20220101 FOR VALUES FROM ('2022-01-01 00:00:00-05') TO ('2022-04-01 00:00:00-04'),
            partman_test.time_taptest_table_p20220401 FOR VALUES FROM ('2022-04-01 00:00:00-04') TO ('2022-07-01 00:00:00-04'),
            partman_test.time_taptest_table_p20220701 FOR VALUES FROM ('2022-07-01 00:00:00-04') TO ('2022-10-01 00:00:00-04'),
            partman_test.time_taptest_table_p20221001 FOR VALUES FROM ('2022-10-01 00:00:00-04') TO ('2023-01-01 00:00:00-05'),
            partman_test.time_taptest_table_p20230101 FOR VALUES FROM ('2023-01-01 00:00:00-05') TO ('2023-04-01 00:00:00-04'),
            partman_test.time_taptest_table_p20230401 FOR VALUES FROM ('2023-04-01 00:00:00-04') TO ('2023-07-01 00:00:00-04'),
            partman_test.time_taptest_table_p20230701 FOR VALUES FROM ('2023-07-01 00:00:00-04') TO ('2023-10-01 00:00:00-04'),
            partman_test.time_taptest_table_p20231001 FOR VALUES FROM ('2023-10-01 00:00:00-04') TO ('2024-01-01 00:00:00-05'),
            partman_test.time_taptest_table_p20240101 FOR VALUES FROM ('2024-01-01 00:00:00-05') TO ('2024-04-01 00:00:00-04'),
            partman_test.time_taptest_table_p20240401 FOR VALUES FROM ('2024-04-01 00:00:00-04') TO ('2024-07-01 00:00:00-04'),
            partman_test.time_taptest_table_p20240701 FOR VALUES FROM ('2024-07-01 00:00:00-04') TO ('2024-10-01 00:00:00-04'),
            partman_test.time_taptest_table_default DEFAULT
```
You can adjust the values of your premake and infinite_time_partitions columns back to their original values if needed.
