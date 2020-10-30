Example Guide On Setting Up Trigger-based Partitioning
========================================

### TODO UPDATE THIS PARAGRAPH ABOUT partitioning exisitng data
This HowTo guide will show you some examples of how to set up simple, single level partitioning It will also show you how to partition data out of a table that has existing data (see **Sub-partition ID->ID->ID**) and undo the partitioning of an existing partition set. For more details on what each function does and the additional features in this extension, please see the **pg_partman.md** documentation file. The examples in this document assume you are running at least 4.4.1 of pg_partman with PostgreSQL 11 or higher. If you need a howto for a previous version, please see an older release available on github to see if one is available. 

Note that all examples here are for native partitioning. If you need to use non-native, trigger-based partitioning, please see the **pg_partman_howto_triggerbased.md** file.

### Simple Time Based: 1 Partition Per Day
For native partitioning, you must start with a parent table that has already been set up to be partitioned in the desired type. Currently pg_partman only supports the RANGE type of partitioning (both for time & id). You cannot turn a non-partitioned table into the parent table of a partitioned set, which can make migration a challenge. This document will show you some techniques for how to manage this later. For now, we will start with a brand new table for this example. Any non-unique indexes can also be added to the parent table in PG11+ and they will automatically be created on all child tables.

```
CREATE SCHEMA IF NOT EXISTS partman_test;

CREATE TABLE partman_test.time_taptest_table 
    (col1 int, 
    col2 text default 'stuff', 
    col3 timestamptz NOT NULL DEFAULT now()) 
PARTITION BY RANGE (col3);

CREATE INDEX ON partman_test.time_taptest_table (col3);
```
```
\d+ partman_test.time_taptest_table 
                               Partitioned table "partman_test.time_taptest_table"
 Column |           Type           | Collation | Nullable |    Default    | Storage  | Stats target | Description 
--------+--------------------------+-----------+----------+---------------+----------+--------------+-------------
 col1   | integer                  |           |          |               | plain    |              | 
 col2   | text                     |           |          | 'stuff'::text | extended |              | 
 col3   | timestamp with time zone |           | not null | now()         | plain    |              | 
Partition key: RANGE (col3)
Indexes:
    "time_taptest_table_col3_idx" btree (col3)
Number of partitions: 0
```

Unique indexes (including primary keys) cannot be created on a natively partitioned parent unless they include the partition key. For time-based partitioning that generally doesn't work out since that would limit only a single timestamp value in each child table. pg_partman helps to manage this by using a template table to manage properties that currently are not supported by native partitioning. Note that this does *not* solve the issue of the constraint *not* being enforced across the entire partition set. See the main documentation to see which properties are managed by the template, depending on the version of PostgreSQL.

For this example, we are going to manually create the template table first so that when we run `create_parent()` the initial child tables that are created will have a primary key. If you do not supply a template table to pg_partman, it will create one for you in the schema that you installed the extension to. However properties you add to that template are only then applied to newly created child tables after that point. You will have to retroactively apply those properties manually to any child tables that already existed.
```
CREATE TABLE partman_test.time_taptest_table_template (LIKE partman_test.time_taptest_table);
ALTER TABLE partman_test.time_taptest_table_template ADD PRIMARY KEY (col1);
```
```
 \d partman_test.time_taptest_table_template
          Table "partman_test.time_taptest_table_template"
 Column |           Type           | Collation | Nullable | Default 
--------+--------------------------+-----------+----------+---------
 col1   | integer                  |           | not null | 
 col2   | text                     |           |          | 
 col3   | timestamp with time zone |           | not null | 
Indexes:
    "time_taptest_table_template_pkey" PRIMARY KEY, btree (col1)
```
```
SELECT partman.create_parent('partman_test.time_taptest_table', 'col3', 'native', 'daily', p_template_table := 'partman_test.time_taptest_table_template');
 create_parent 
---------------
 t
(1 row)
```
```
keith@keith=# \d+ partman_test.time_taptest_table
                               Partitioned table "partman_test.time_taptest_table"
 Column |           Type           | Collation | Nullable |    Default    | Storage  | Stats target | Description 
--------+--------------------------+-----------+----------+---------------+----------+--------------+-------------
 col1   | integer                  |           |          |               | plain    |              | 
 col2   | text                     |           |          | 'stuff'::text | extended |              | 
 col3   | timestamp with time zone |           | not null | now()         | plain    |              | 
Partition key: RANGE (col3)
Indexes:
    "time_taptest_table_col3_idx" btree (col3)
Partitions: partman_test.time_taptest_table_p2020_10_26 FOR VALUES FROM ('2020-10-26 00:00:00-04') TO ('2020-10-27 00:00:00-04'),
            partman_test.time_taptest_table_p2020_10_27 FOR VALUES FROM ('2020-10-27 00:00:00-04') TO ('2020-10-28 00:00:00-04'),
            partman_test.time_taptest_table_p2020_10_28 FOR VALUES FROM ('2020-10-28 00:00:00-04') TO ('2020-10-29 00:00:00-04'),
            partman_test.time_taptest_table_p2020_10_29 FOR VALUES FROM ('2020-10-29 00:00:00-04') TO ('2020-10-30 00:00:00-04'),
            partman_test.time_taptest_table_p2020_10_30 FOR VALUES FROM ('2020-10-30 00:00:00-04') TO ('2020-10-31 00:00:00-04'),
            partman_test.time_taptest_table_p2020_10_31 FOR VALUES FROM ('2020-10-31 00:00:00-04') TO ('2020-11-01 00:00:00-04'),
            partman_test.time_taptest_table_p2020_11_01 FOR VALUES FROM ('2020-11-01 00:00:00-04') TO ('2020-11-02 00:00:00-05'),
            partman_test.time_taptest_table_p2020_11_02 FOR VALUES FROM ('2020-11-02 00:00:00-05') TO ('2020-11-03 00:00:00-05'),
            partman_test.time_taptest_table_p2020_11_03 FOR VALUES FROM ('2020-11-03 00:00:00-05') TO ('2020-11-04 00:00:00-05'),
            partman_test.time_taptest_table_default DEFAULT
```
```
keith@keith=# \d+ partman_test.time_taptest_table_p2020_10_26
                               Table "partman_test.time_taptest_table_p2020_10_26"
 Column |           Type           | Collation | Nullable |    Default    | Storage  | Stats target | Description 
--------+--------------------------+-----------+----------+---------------+----------+--------------+-------------
 col1   | integer                  |           | not null |               | plain    |              | 
 col2   | text                     |           |          | 'stuff'::text | extended |              | 
 col3   | timestamp with time zone |           | not null | now()         | plain    |              | 
Partition of: partman_test.time_taptest_table FOR VALUES FROM ('2020-10-26 00:00:00-04') TO ('2020-10-27 00:00:00-04')
Partition constraint: ((col3 IS NOT NULL) AND (col3 >= '2020-10-26 00:00:00-04'::timestamp with time zone) AND (col3 < '2020-10-27 00:00:00-04'::timestamp with time zone))
Indexes:
    "time_taptest_table_p2020_10_26_pkey" PRIMARY KEY, btree (col1)
    "time_taptest_table_p2020_10_26_col3_idx" btree (col3)
Access method: heap

```

### Simple Serial ID: 1 Partition Per 10 ID Values Starting With Empty Table
For this use-case, the template table is not created manually before calling `create_parent()`. So it shows that if a primary/unique key is added later, it does not apply to the currently existing child tables. That will have to be done manually. 

```
CREATE TABLE partman_test.id_taptest_table (
    col1 bigint 
    , col2 text not null
    , col3 timestamptz DEFAULT now()
    , col4 text) PARTITION BY RANGE (col1);

CREATE INDEX ON partman_test.id_taptest_table (col1);
```
```
keith@keith=# \d+ partman_test.id_taptest_table 
                             Partitioned table "partman_test.id_taptest_table"
 Column |           Type           | Collation | Nullable | Default | Storage  | Stats target | Description 
--------+--------------------------+-----------+----------+---------+----------+--------------+-------------
 col1   | bigint                   |           |          |         | plain    |              | 
 col2   | text                     |           | not null |         | extended |              | 
 col3   | timestamp with time zone |           |          | now()   | plain    |              | 
 col4   | text                     |           |          |         | extended |              | 
Partition key: RANGE (col1)
Indexes:
    "id_taptest_table_col1_idx" btree (col1)
Number of partitions: 0
```
```

keith@keith=# SELECT partman.create_parent('partman_test.id_taptest_table', 'col1', 'native', '10');
 create_parent 
---------------
 t
(1 row)
```
```
\d+ partman_test.id_taptest_table
                             Partitioned table "partman_test.id_taptest_table"
 Column |           Type           | Collation | Nullable | Default | Storage  | Stats target | Description 
--------+--------------------------+-----------+----------+---------+----------+--------------+-------------
 col1   | bigint                   |           |          |         | plain    |              | 
 col2   | text                     |           | not null |         | extended |              | 
 col3   | timestamp with time zone |           |          | now()   | plain    |              | 
 col4   | text                     |           |          |         | extended |              | 
Partition key: RANGE (col1)
Indexes:
    "id_taptest_table_col1_idx" btree (col1)
Partitions: partman_test.id_taptest_table_p0 FOR VALUES FROM ('0') TO ('10'),
            partman_test.id_taptest_table_p10 FOR VALUES FROM ('10') TO ('20'),
            partman_test.id_taptest_table_p20 FOR VALUES FROM ('20') TO ('30'),
            partman_test.id_taptest_table_p30 FOR VALUES FROM ('30') TO ('40'),
            partman_test.id_taptest_table_p40 FOR VALUES FROM ('40') TO ('50'),
            partman_test.id_taptest_table_default DEFAULT
```

You can see the name of the template table by looking in the pg_partman configration for that parent table

```
select template_table from partman.part_config where parent_table = 'partman_test.id_taptest_table';
                 template_table                 
------------------------------------------------
 partman.template_partman_test_id_taptest_table
```
```
ALTER TABLE partman.template_partman_test_id_taptest_table ADD PRIMARY KEY (col2);
```
Now if we add some data and run maintenance again to create new child tables...
```
INSERT INTO partman_test.id_taptest_table (col1, col2) VALUES (generate_series(1,20), generate_series(1,20)::text||'stuff'::text);

CALL partman.run_maintenance_proc();

\d+ partman_test.id_taptest_table
                             Partitioned table "partman_test.id_taptest_table"
 Column |           Type           | Collation | Nullable | Default | Storage  | Stats target | Description 
--------+--------------------------+-----------+----------+---------+----------+--------------+-------------
 col1   | bigint                   |           |          |         | plain    |              | 
 col2   | text                     |           | not null |         | extended |              | 
 col3   | timestamp with time zone |           |          | now()   | plain    |              | 
 col4   | text                     |           |          |         | extended |              | 
Partition key: RANGE (col1)
Indexes:
    "id_taptest_table_col1_idx" btree (col1)
Partitions: partman_test.id_taptest_table_p0 FOR VALUES FROM ('0') TO ('10'),
            partman_test.id_taptest_table_p10 FOR VALUES FROM ('10') TO ('20'),
            partman_test.id_taptest_table_p20 FOR VALUES FROM ('20') TO ('30'),
            partman_test.id_taptest_table_p30 FOR VALUES FROM ('30') TO ('40'),
            partman_test.id_taptest_table_p40 FOR VALUES FROM ('40') TO ('50'),
            partman_test.id_taptest_table_p50 FOR VALUES FROM ('50') TO ('60'),
            partman_test.id_taptest_table_p60 FOR VALUES FROM ('60') TO ('70'),
            partman_test.id_taptest_table_default DEFAULT
```
... you'll see that only the new child tables (p50 & p60) have that primary key and the original tables do not (p40 and earlier).
```
\d partman_test.id_taptest_table_p40
             Table "partman_test.id_taptest_table_p40"
 Column |           Type           | Collation | Nullable | Default 
--------+--------------------------+-----------+----------+---------
 col1   | bigint                   |           |          | 
 col2   | text                     |           | not null | 
 col3   | timestamp with time zone |           |          | now()
 col4   | text                     |           |          | 
Partition of: partman_test.id_taptest_table FOR VALUES FROM ('40') TO ('50')
Indexes:
    "id_taptest_table_p40_col1_idx" btree (col1)

\d partman_test.id_taptest_table_p50
             Table "partman_test.id_taptest_table_p50"
 Column |           Type           | Collation | Nullable | Default 
--------+--------------------------+-----------+----------+---------
 col1   | bigint                   |           |          | 
 col2   | text                     |           | not null | 
 col3   | timestamp with time zone |           |          | now()
 col4   | text                     |           |          | 
Partition of: partman_test.id_taptest_table FOR VALUES FROM ('50') TO ('60')
Indexes:
    "id_taptest_table_p50_pkey" PRIMARY KEY, btree (col2)
    "id_taptest_table_p50_col1_idx" btree (col1)

\d partman_test.id_taptest_table_p60
             Table "partman_test.id_taptest_table_p60"
 Column |           Type           | Collation | Nullable | Default 
--------+--------------------------+-----------+----------+---------
 col1   | bigint                   |           |          | 
 col2   | text                     |           | not null | 
 col3   | timestamp with time zone |           |          | now()
 col4   | text                     |           |          | 
Partition of: partman_test.id_taptest_table FOR VALUES FROM ('60') TO ('70')
Indexes:
    "id_taptest_table_p60_pkey" PRIMARY KEY, btree (col2)
    "id_taptest_table_p60_col1_idx" btree (col1)
```
Add them manually:
```
ALTER TABLE partman_test.id_taptest_table_p0 ADD PRIMARY KEY (col2);
ALTER TABLE partman_test.id_taptest_table_p10 ADD PRIMARY KEY (col2);
ALTER TABLE partman_test.id_taptest_table_p20 ADD PRIMARY KEY (col2);
ALTER TABLE partman_test.id_taptest_table_p30 ADD PRIMARY KEY (col2);
ALTER TABLE partman_test.id_taptest_table_p40 ADD PRIMARY KEY (col2);
```
