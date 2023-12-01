# Migrating From Trigger-based Partitioning To Native Declarative Partitioning

This document will cover how to migrate a partition set using the old method of triggers/inheritance/constraints to a partition set using the native features found in PostgreSQL. This document assumes you are on at least PostgreSQL 14. This does not migrate the partition set fully to be used by pg_partman, it just provides the general guidance for the trigger->native process. Please See the separate document `migrate_to_partman.md` for migrating your partition sets to pg_partman.

For sub-partitioning you should be able to follow all the same processes here, but you will have to work from the lowest level upward and perform the migration on each sub-parent all the way to the top-level parent.

As always, if you can first test this migration on a development system, it is highly recommended. The full data set is not needed to test this and just the schema with a smaller set of data in each child should be sufficient enough to make sure it works properly.

This is how our partition set currently looks before migration:

```sql
\d+ partman_test.time_taptest_table
                                         Table "partman_test.time_taptest_table"
 Column |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 col1   | integer                  |           | not null |         | plain    |             |              | 
 col2   | text                     |           |          |         | extended |             |              | 
 col3   | timestamp with time zone |           | not null | now()   | plain    |             |              | 
Indexes:
    "time_taptest_table_pkey" PRIMARY KEY, btree (col1)
Triggers:
    time_taptest_table_part_trig BEFORE INSERT ON partman_test.time_taptest_table FOR EACH ROW EXECUTE FUNCTION partman_test.time_taptest_table_part_trig_func()
Child tables: partman_test.time_taptest_table_p2023_03_26,
              partman_test.time_taptest_table_p2023_03_27,
              partman_test.time_taptest_table_p2023_03_28,
              partman_test.time_taptest_table_p2023_03_29,
              partman_test.time_taptest_table_p2023_03_30,
              partman_test.time_taptest_table_p2023_03_31,
              partman_test.time_taptest_table_p2023_04_01,
              partman_test.time_taptest_table_p2023_04_02,
              partman_test.time_taptest_table_p2023_04_03,
              partman_test.time_taptest_table_p2023_04_04,
              partman_test.time_taptest_table_p2023_04_05,
              partman_test.time_taptest_table_p2023_04_06,
              partman_test.time_taptest_table_p2023_04_07,
              partman_test.time_taptest_table_p2023_04_08,
              partman_test.time_taptest_table_p2023_04_09
Access method: heap
```

If your trigger-based partition set happens to be managed by pg_partman version prior to 5.0.0, it is best to remove it from partman management. This can be done by deleting it from the `part_config` and `part_config_sub` tables (if sub-partitioned, ensure all child tables are removed as well). After it has been migrated to native partitioning, see the Migrating to pg_partman document mentioned above to return it to being managed by partman.
```sql
DELETE FROM partman.part_config WHERE parent_table = 'partman_test.time_taptest_table';
```

If it is not managed by pg_partman and you have some other method of automated maintenance, ensure that process is disabled.

Next, we need to create a new parent table using native partitioning since you cannot currently convert an existing table into a native partition parent. Note in this case our original table had a primary key on `col1`. Since `col1` is not part of the partition key, native partitioning does not allow us to declare it as a primary key on the top level table. If you still need this as a primary key, pg_partman provides a template table you can set this on, but it will still not enforce uniqueness across the entire partition set, only on a per-child basis similar to how it worked before native.

Please see the `Child Table Property Inheritance` section of `docs/pg_partman.md` for which properties can be set on the native parent and which must be managed via the template .
  
```sql
CREATE TABLE partman_test.time_taptest_table_native 
    (col1 int, col2 text default 'stuff', col3 timestamptz NOT NULL DEFAULT now()) 
    PARTITION BY RANGE (col3);

CREATE INDEX ON partman_test.time_taptest_table_native (col3);
```

Next check what the ownership and privileges on your original table were and ensure they exist on the new parent table. This will ensure all access to the table works the same after the migration. By default with native partitioning, privileges are no longer granted on child tables to provide direct access to them. If you'd like to keep that behavior, set the `inherit_privileges` column in `part_config` (and part_config_sub if needed) to true. 
```sql
\dt partman_test.time_taptest_table
                     List of relations
    Schema    |        Name        | Type  |     Owner     
--------------+--------------------+-------+---------------
 partman_test | time_taptest_table | table | partman_owner
(1 row)

\dp+ partman_test.time_taptest_table
                                               Access privileges
    Schema    |        Name        | Type  |          Access privileges          | Column privileges | Policies 
--------------+--------------------+-------+-------------------------------------+-------------------+----------
 partman_test | time_taptest_table | table | partman_owner=arwdDxt/partman_owner+|                   | 
              |                    |       | partman_basic=arwd/partman_owner   +|                   | 
              |                    |       | testing=r/partman_owner             |                   | 
(1 row)
```
```sql
ALTER TABLE partman_test.time_taptest_table_native OWNER TO partman_owner;
GRANT SELECT, INSERT, UPDATE, DELETE ON partman_test.time_taptest_table_native TO partman_basic;
GRANT SELECT ON partman_test.time_taptest_table_native TO testing;
```

It is best to halt all activity on the original table during the migration process to avoid any issues. This can be done by either revoking all permissions to the table temporarily or by taking out an exclusive lock on the parent table and running all of these steps in a single transaction. The transactional method is highly recommended for the simple fact that if you run into any issues before you've completed the migration process, you can simply rollback and return to the state your database was in before the migration started.
```sql
BEGIN;
LOCK TABLE partman_test.time_taptest_table IN ACCESS EXCLUSIVE MODE NOWAIT;
```
If this is a subpartitioned table, the lock on the top-level parent should lock out access on all child tables as long as you don't use the ONLY clause.

The first major step in this migration process is now to uninherit all the child tables from the old parent. You can use a query like the one below to generate the ALTER TABLE statements to uninherit all child tables from the given parent table. It's best to use generated SQL like this to avoid typos, especially with very large partition sets:

DO NOT RUN THE RESULTING STATEMENTS YET. A future query will not work if the child tables are no longer part of the inheritance set.

```sql
SELECT format('ALTER TABLE %s NO INHERIT %s;', inhrelid::regclass, inhparent::regclass)
FROM pg_inherits 
WHERE inhparent::regclass = 'partman_test.time_taptest_table'::regclass;
                                              ?column?                                               
-----------------------------------------------------------------------------------------------------
 ALTER TABLE partman_test.time_taptest_table_p2023_03_26 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_03_27 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_03_28 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_03_29 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_03_30 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_03_31 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_04_01 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_04_02 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_04_03 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_04_04 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_04_05 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_04_06 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_04_07 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_04_08 NO INHERIT partman_test.time_taptest_table;
 ALTER TABLE partman_test.time_taptest_table_p2023_04_09 NO INHERIT partman_test.time_taptest_table;
(15 rows)
```

Again, DO NOT RUN THESE STATEMENTS YET. The following query will not work if the child tables are no longer part of the inheritance set.

For any partition sets, even those not managed by pg_partman, the next step is that you need to figure out the boundary values of your existing child tables and feed those to the ATTACH PARTITION command used in native partitioning. You will have to figure out a method to determine the boundaries of your child tables to be able to convert them to the syntax needed for PostgreSQL's declarative commands. In our case here, our child table's suffixes have a fixed naming pattern (`YYYY_MM_DD`) that can be parsed to determine the starting boundary value. In this case we'll also need to know the partitioning interval (`1 day`) to be able to calculate the boundary end time.

If your child table names do not have a usable pattern like this, you'll have to figure out some method of determining each child table's boundaries. 

Again, we can use some sql to generate statements to re-attach the children to the new parent:
```sql
WITH child_tables AS (
    SELECT 
          inhrelid::regclass::text AS child_tablename_safe
        , relname AS child_tablename  -- need unquoted name for parsing
    FROM pg_inherits
    JOIN pg_class c ON inhrelid = c.oid
    WHERE inhparent = 'partman_test.time_taptest_table'::regclass
)
SELECT format(
    'ALTER TABLE %s ATTACH PARTITION %s FOR VALUES FROM (%L) TO (%L);'
    , 'partman_test.time_taptest_table_native'::regclass
    , child_tablename_safe
    , to_timestamp(right(x.child_tablename, 10), 'YYYY_MM_DD')
    , to_timestamp(right(x.child_tablename, 10), 'YYYY_MM_DD')+'1 day'::interval
)
FROM child_tables x;
                                                                                         ?column?                                                                                          
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_03_26 FOR VALUES FROM ('2023-03-26 00:00:00-04') TO ('2023-03-27 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_03_27 FOR VALUES FROM ('2023-03-27 00:00:00-04') TO ('2023-03-28 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_03_28 FOR VALUES FROM ('2023-03-28 00:00:00-04') TO ('2023-03-29 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_03_29 FOR VALUES FROM ('2023-03-29 00:00:00-04') TO ('2023-03-30 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_03_30 FOR VALUES FROM ('2023-03-30 00:00:00-04') TO ('2023-03-31 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_03_31 FOR VALUES FROM ('2023-03-31 00:00:00-04') TO ('2023-04-01 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_04_01 FOR VALUES FROM ('2023-04-01 00:00:00-04') TO ('2023-04-02 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_04_02 FOR VALUES FROM ('2023-04-02 00:00:00-04') TO ('2023-04-03 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_04_03 FOR VALUES FROM ('2023-04-03 00:00:00-04') TO ('2023-04-04 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_04_04 FOR VALUES FROM ('2023-04-04 00:00:00-04') TO ('2023-04-05 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_04_05 FOR VALUES FROM ('2023-04-05 00:00:00-04') TO ('2023-04-06 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_04_06 FOR VALUES FROM ('2023-04-06 00:00:00-04') TO ('2023-04-07 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_04_07 FOR VALUES FROM ('2023-04-07 00:00:00-04') TO ('2023-04-08 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_04_08 FOR VALUES FROM ('2023-04-08 00:00:00-04') TO ('2023-04-09 00:00:00-04');
 ALTER TABLE partman_test.time_taptest_table_native ATTACH PARTITION partman_test.time_taptest_table_p2023_04_09 FOR VALUES FROM ('2023-04-09 00:00:00-04') TO ('2023-04-10 00:00:00-04');
(15 rows)

```
We can now run these two sets of ALTER TABLE statements to first uninherit them from the old trigger-based parent and attach them to the new native parent. After doing so, the old trigger-based parent should have no longer have children:
```sql
\d+ partman_test.time_taptest_table

                                         Table "partman_test.time_taptest_table"
 Column |           Type           | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+--------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 col1   | integer                  |           | not null |         | plain    |             |              | 
 col2   | text                     |           |          |         | extended |             |              | 
 col3   | timestamp with time zone |           | not null | now()   | plain    |             |              | 
Indexes:
    "time_taptest_table_pkey" PRIMARY KEY, btree (col1)
Triggers:
    time_taptest_table_part_trig BEFORE INSERT ON partman_test.time_taptest_table FOR EACH ROW EXECUTE FUNCTION partman_test.time_taptest_table_part_trig_func()
Access method: heap
```
And our new native parent should have now adopted all its new children:
```sql
\d+ partman_test.time_taptest_table_native
                                   Partitioned table "partman_test.time_taptest_table_native"
 Column |           Type           | Collation | Nullable |    Default    | Storage  | Compression | Stats target | Description 
--------+--------------------------+-----------+----------+---------------+----------+-------------+--------------+-------------
 col1   | integer                  |           |          |               | plain    |             |              | 
 col2   | text                     |           |          | 'stuff'::text | extended |             |              | 
 col3   | timestamp with time zone |           | not null | now()         | plain    |             |              | 
Partition key: RANGE (col3)
Indexes:
    "time_taptest_table_native_col3_idx" btree (col3)
Partitions: partman_test.time_taptest_table_p2023_03_26 FOR VALUES FROM ('2023-03-26 00:00:00-04') TO ('2023-03-27 00:00:00-04'),
            partman_test.time_taptest_table_p2023_03_27 FOR VALUES FROM ('2023-03-27 00:00:00-04') TO ('2023-03-28 00:00:00-04'),
            partman_test.time_taptest_table_p2023_03_28 FOR VALUES FROM ('2023-03-28 00:00:00-04') TO ('2023-03-29 00:00:00-04'),
            partman_test.time_taptest_table_p2023_03_29 FOR VALUES FROM ('2023-03-29 00:00:00-04') TO ('2023-03-30 00:00:00-04'),
            partman_test.time_taptest_table_p2023_03_30 FOR VALUES FROM ('2023-03-30 00:00:00-04') TO ('2023-03-31 00:00:00-04'),
            partman_test.time_taptest_table_p2023_03_31 FOR VALUES FROM ('2023-03-31 00:00:00-04') TO ('2023-04-01 00:00:00-04'),
            partman_test.time_taptest_table_p2023_04_01 FOR VALUES FROM ('2023-04-01 00:00:00-04') TO ('2023-04-02 00:00:00-04'),
            partman_test.time_taptest_table_p2023_04_02 FOR VALUES FROM ('2023-04-02 00:00:00-04') TO ('2023-04-03 00:00:00-04'),
            partman_test.time_taptest_table_p2023_04_03 FOR VALUES FROM ('2023-04-03 00:00:00-04') TO ('2023-04-04 00:00:00-04'),
            partman_test.time_taptest_table_p2023_04_04 FOR VALUES FROM ('2023-04-04 00:00:00-04') TO ('2023-04-05 00:00:00-04'),
            partman_test.time_taptest_table_p2023_04_05 FOR VALUES FROM ('2023-04-05 00:00:00-04') TO ('2023-04-06 00:00:00-04'),
            partman_test.time_taptest_table_p2023_04_06 FOR VALUES FROM ('2023-04-06 00:00:00-04') TO ('2023-04-07 00:00:00-04'),
            partman_test.time_taptest_table_p2023_04_07 FOR VALUES FROM ('2023-04-07 00:00:00-04') TO ('2023-04-08 00:00:00-04'),
            partman_test.time_taptest_table_p2023_04_08 FOR VALUES FROM ('2023-04-08 00:00:00-04') TO ('2023-04-09 00:00:00-04'),
            partman_test.time_taptest_table_p2023_04_09 FOR VALUES FROM ('2023-04-09 00:00:00-04') TO ('2023-04-10 00:00:00-04')

```
Next is to swap the names of your old trigger-based parent and the new native parent. 
```sql
ALTER TABLE partman_test.time_taptest_table RENAME TO time_taptest_table_old;
ALTER TABLE partman_test.time_taptest_table_native RENAME TO time_taptest_table;
```
PG11+ supports the feature of a default partition to catch any data that doesn't have a matching child. If your table names are particularly long, ensure that adding the `_default` suffix doesn't get truncated unexpectedly. The suffix isn't required for functionality, but provides good context for what the table is for, so it's better to shorten the table name itself to fit the suffix.
```sql
CREATE TABLE partman_test.time_taptest_table_default (LIKE partman_test.time_taptest_table INCLUDING ALL);
ALTER TABLE partman_test.time_taptest_table ATTACH PARTITION partman_test.time_taptest_table_default DEFAULT;
```

There was a primary key on the original parent table, but that is not possible with native partitioning unless the primary key also includes the partition key. This is typically not practical in time-based partitioning. You can place a primary key on each individual child table, but that only enforces the constraint for that child table, not across the entire partition set. You can add a primary key to each individual table using similar SQL generation above, but if you'd like a method to manage adding these to any new child tables, please see the features available in pg_partman.

If you've run this process inside a transaction, be sure to commit your work now:
```sql
COMMIT;
```
This should complete the migration process. If you'd like to migrate your partition set to be managed by pg_partman, please see the `migrate_to_partman.md` documentation file.
