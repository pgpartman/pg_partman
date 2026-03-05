-- ########## ID TESTS ##########
-- Additional tests:
    -- backfill gap in child tables, start with higher number
    -- pre-created template table with indexes
    -- old create_parent() alias
    -- Test relopt inheritance (regular table and toast)

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(47);
CREATE SCHEMA partman_test;

CREATE TABLE partman_test.id_taptest_table (
    col1 bigint
    , col2 text not null default 'stuff'
    , col3 timestamptz DEFAULT now()
    , col4 text) PARTITION BY RANGE (col1);
-- Template table
CREATE TABLE partman_test.template_id_taptest_table (LIKE partman_test.id_taptest_table);

ALTER TABLE partman_test.id_taptest_table ADD PRIMARY KEY (col1);
CREATE INDEX ON partman_test.id_taptest_table (col3);

ALTER TABLE partman_test.template_id_taptest_table SET (fillfactor = 75);
ALTER TABLE partman_test.template_id_taptest_table SET (toast.autovacuum_vacuum_threshold = 120);

-- Always create the index on the template also so that we can test excluding duplicates.
CREATE INDEX ON partman_test.template_id_taptest_table (col3);

-- Regular unique indexes do not work the partition key isn't included
CREATE UNIQUE INDEX ON partman_test.template_id_taptest_table (col4);

SELECT create_parent('partman_test.id_taptest_table', 'col1', '10', p_jobmon := false, p_start_partition := '3000000000', p_template_table := 'partman_test.template_id_taptest_table');

INSERT INTO partman_test.id_taptest_table (col1, col4) VALUES (generate_series(3000000001,3000000009), 'stuff'||generate_series(3000000001,3000000009));

SELECT has_table('partman_test', 'id_taptest_table_p3000000000', 'Check id_taptest_table_p3000000000 exists');
SELECT has_table('partman_test', 'id_taptest_table_p3000000010', 'Check id_taptest_table_p3000000010 exists');
SELECT has_table('partman_test', 'id_taptest_table_p3000000020', 'Check id_taptest_table_p3000000020 exists');
SELECT has_table('partman_test', 'id_taptest_table_p3000000030', 'Check id_taptest_table_p3000000030 exists');
SELECT has_table('partman_test', 'id_taptest_table_p3000000040', 'Check id_taptest_table_p3000000040 exists');
SELECT hasnt_table('partman_test', 'id_taptest_table_p3000000050', 'Check id_taptest_table_p3000000050 doesn''t exists yet');
SELECT col_is_pk('partman_test', 'id_taptest_table_p3000000000', ARRAY['col1'], 'Check for primary key in id_taptest_table_p3000000000');
SELECT col_is_pk('partman_test', 'id_taptest_table_p3000000010', ARRAY['col1'], 'Check for primary key in id_taptest_table_p3000000010');
SELECT col_is_pk('partman_test', 'id_taptest_table_p3000000020', ARRAY['col1'], 'Check for primary key in id_taptest_table_p3000000020');
SELECT col_is_pk('partman_test', 'id_taptest_table_p3000000030', ARRAY['col1'], 'Check for primary key in id_taptest_table_p3000000030');
SELECT col_is_pk('partman_test', 'id_taptest_table_p3000000040', ARRAY['col1'], 'Check for primary key in id_taptest_table_p3000000040');
SELECT is_indexed('partman_test', 'id_taptest_table_p3000000000', 'col4', 'Check that unique index was inherited to id_taptest_table_p3000000000');
SELECT is_indexed('partman_test', 'id_taptest_table_p3000000010', 'col4', 'Check that unique index was inherited to id_taptest_table_p3000000010');
SELECT is_indexed('partman_test', 'id_taptest_table_p3000000020', 'col4', 'Check that unique index was inherited to id_taptest_table_p3000000020');
SELECT is_indexed('partman_test', 'id_taptest_table_p3000000030', 'col4', 'Check that unique index was inherited to id_taptest_table_p3000000030');
SELECT is_indexed('partman_test', 'id_taptest_table_p3000000040', 'col4', 'Check that unique index was inherited to id_taptest_table_p3000000040');
SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table', 'Check that parent table has had data moved to partition');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table', ARRAY[9], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p3000000000', ARRAY[9], 'Check count from id_taptest_table_p3000000000');

-- Check reloptions set for child table
SELECT results_eq('WITH relopt AS (
    SELECT unnest(reloptions) AS relopt FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relname = ''id_taptest_table_p3000000000''
        AND n.nspname = ''partman_test''
)
SELECT count(*)::int from relopt WHERE relopt = ''fillfactor=75'''

    , ARRAY[1]
    , 'Check reloptions for id_taptest_table_p3000000000 child table'
);
SELECT results_eq('WITH relopt AS (
    SELECT unnest(reloptions) AS relopt FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relname = ''id_taptest_table_p3000000030''
        AND n.nspname = ''partman_test''
)
SELECT count(*)::int from relopt WHERE relopt = ''fillfactor=75'''

    , ARRAY[1]
    , 'Check reloptions for id_taptest_table_p3000000030 child table'
);

-- Check reloptions set for toast

SELECT results_eq('WITH child_toast AS (
    SELECT reltoastrelid
    FROM pg_class c1
    JOIN pg_namespace n ON c1.relnamespace = n.oid
    WHERE c1.relname = ''id_taptest_table_p3000000000''
    AND n.nspname = ''partman_test''
), toast_relopt AS (
    SELECT unnest(reloptions) AS relopt FROM pg_class c
    JOIN child_toast ct ON c.oid = ct.reltoastrelid
)
SELECT count(*)::int from toast_relopt WHERE relopt = ''autovacuum_vacuum_threshold=120'''
    , ARRAY[1]
    , 'Check reloptions for id_taptest_table_p3000000000 toast table'
);
SELECT results_eq('WITH child_toast AS (
    SELECT reltoastrelid
    FROM pg_class c1
    JOIN pg_namespace n ON c1.relnamespace = n.oid
    WHERE c1.relname = ''id_taptest_table_p3000000040''
    AND n.nspname = ''partman_test''
), toast_relopt AS (
    SELECT unnest(reloptions) AS relopt FROM pg_class c
    JOIN child_toast ct ON c.oid = ct.reltoastrelid
)
SELECT count(*)::int from toast_relopt WHERE relopt = ''autovacuum_vacuum_threshold=120'''
    , ARRAY[1]
    , 'Check reloptions for id_taptest_table_p3000000040 toast table'
);

SELECT run_maintenance();
INSERT INTO partman_test.id_taptest_table (col1, col4) VALUES (generate_series(3000000010,3000000025), 'stuff'||generate_series(3000000010,3000000025));
-- Run again to make new partition based on latest data
SELECT run_maintenance();

SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table_default', 'Check that default table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p3000000010', ARRAY[10], 'Check count from id_taptest_table_p3000000010');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p3000000020', ARRAY[6], 'Check count from id_taptest_table_p3000000020');

SELECT has_table('partman_test', 'id_taptest_table_p3000000050', 'Check id_taptest_table_p3000000050 exists');
SELECT has_table('partman_test', 'id_taptest_table_p3000000060', 'Check id_taptest_table_p3000000060 exists yet');
SELECT hasnt_table('partman_test', 'id_taptest_table_p3000000070', 'Check id_taptest_table_p3000000070 doesn''t exists yet');

INSERT INTO partman_test.id_taptest_table (col1, col4) VALUES (generate_series(3000000026,3000000038), 'stuff'||generate_series(3000000026,3000000038));

SELECT run_maintenance();

SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table', 'Check that parent table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table', ARRAY[38], 'Check count from id_taptest_table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p3000000020', ARRAY[10], 'Check count from id_taptest_table_p3000000020');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p3000000030', ARRAY[9], 'Check count from id_taptest_table_p3000000030');

SELECT has_table('partman_test', 'id_taptest_table_p3000000070', 'Check id_taptest_table_p3000000070 exists');
SELECT hasnt_table('partman_test', 'id_taptest_table_p3000000080', 'Check id_taptest_table_p3000000080 doesn''t exists yet');
SELECT col_is_pk('partman_test', 'id_taptest_table_p3000000060', ARRAY['col1'], 'Check for primary key in id_taptest_table_p3000000060');
SELECT col_is_pk('partman_test', 'id_taptest_table_p3000000070', ARRAY['col1'], 'Check for primary key in id_taptest_table_p3000000070');

SELECT results_eq('WITH relopt AS (
    SELECT unnest(reloptions) AS relopt FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE c.relname = ''id_taptest_table_p3000000070''
        AND n.nspname = ''partman_test''
)
SELECT count(*)::int from relopt WHERE relopt = ''fillfactor=75'''

    , ARRAY[1]
    , 'Check reloptions for id_taptest_table_p3000000070 child table'
);
SELECT results_eq('WITH child_toast AS (
    SELECT reltoastrelid
    FROM pg_class c1
    JOIN pg_namespace n ON c1.relnamespace = n.oid
    WHERE c1.relname = ''id_taptest_table_p3000000070''
    AND n.nspname = ''partman_test''
), toast_relopt AS (
    SELECT unnest(reloptions) AS relopt FROM pg_class c
    JOIN child_toast ct ON c.oid = ct.reltoastrelid
)
SELECT count(*)::int from toast_relopt WHERE relopt = ''autovacuum_vacuum_threshold=120'''
    , ARRAY[1]
    , 'Check reloptions for id_taptest_table_p3000000070 toast table'
);

DROP TABLE partman_test.id_taptest_table_p3000000020;
DROP TABLE partman_test.id_taptest_table_p3000000040;
DROP TABLE partman_test.id_taptest_table_p3000000050;
DROP TABLE partman_test.id_taptest_table_p3000000060;

SELECT hasnt_table('partman_test', 'id_taptest_table_p3000000020', 'Check id_taptest_table_p3000000020 was dropped');
SELECT hasnt_table('partman_test', 'id_taptest_table_p3000000040', 'Check id_taptest_table_p3000000040 was dropped');
SELECT hasnt_table('partman_test', 'id_taptest_table_p3000000050', 'Check id_taptest_table_p3000000050 was dropped');
SELECT hasnt_table('partman_test', 'id_taptest_table_p3000000060', 'Check id_taptest_table_p3000000060 was dropped');

SELECT partition_gap_fill('partman_test.id_taptest_table');

SELECT has_table('partman_test', 'id_taptest_table_p3000000020', 'Check id_taptest_table_p3000000020 was recreated');
SELECT has_table('partman_test', 'id_taptest_table_p3000000040', 'Check id_taptest_table_p3000000040 was recreated');
SELECT has_table('partman_test', 'id_taptest_table_p3000000050', 'Check id_taptest_table_p3000000050 was recreated');
SELECT has_table('partman_test', 'id_taptest_table_p3000000060', 'Check id_taptest_table_p3000000060 was recreated');

SELECT * FROM finish();
ROLLBACK;
