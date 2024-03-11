-- ########## NUMERIC TESTS ##########
-- Additional tests:
    -- pre-created template table and passing to create_parent. Should allow indexes to be made for initial children.

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(47);
CREATE SCHEMA partman_test;

CREATE TABLE partman_test.id_taptest_table
    (col1 numeric(9,2) PRIMARY KEY NOT NULL
        , col2 text not null default 'stuff'
        , col3 timestamptz DEFAULT now()
        , col4 text)
    PARTITION BY RANGE (col1);
CREATE TABLE partman_test.undo_taptest (LIKE partman_test.id_taptest_table INCLUDING ALL);
-- Template table
CREATE TABLE partman_test.template_id_taptest_table (LIKE partman_test.id_taptest_table);

CREATE INDEX ON partman_test.id_taptest_table (col1);

-- Regular unique indexes do not work on native if the partition key isn't included
CREATE UNIQUE INDEX ON partman_test.template_id_taptest_table (col4);

-- Create publication and add parent table to it
CREATE PUBLICATION partman_test_pub FOR TABLE partman_test.id_taptest_table;

SELECT create_parent('partman_test.id_taptest_table', 'col1', '100', p_template_table := 'partman_test.template_id_taptest_table');

INSERT INTO partman_test.id_taptest_table (col1, col4) VALUES (generate_series(1.5,90.5), 'stuff'||generate_series(1.5,90.5));

SELECT has_table('partman_test', 'id_taptest_table_p0', 'Check id_taptest_table_p0 exists');
SELECT has_table('partman_test', 'id_taptest_table_p100', 'Check id_taptest_table_p100 exists');
SELECT has_table('partman_test', 'id_taptest_table_p200', 'Check id_taptest_table_p200 exists');
SELECT has_table('partman_test', 'id_taptest_table_p300', 'Check id_taptest_table_p300 exists');
SELECT has_table('partman_test', 'id_taptest_table_p400', 'Check id_taptest_table_p400 exists');
SELECT has_table('partman_test', 'id_taptest_table_default', 'Check id_taptest_table_default exists');
SELECT hasnt_table('partman_test', 'id_taptest_table_p500', 'Check id_taptest_table_p500 doesn''t exists yet');
SELECT is_indexed('partman_test', 'id_taptest_table_p0', 'col4', 'Check that unique index was inherited to id_taptest_table_p0');
SELECT is_indexed('partman_test', 'id_taptest_table_p100', 'col4', 'Check that unique index was inherited to id_taptest_table_p100');
SELECT is_indexed('partman_test', 'id_taptest_table_p200', 'col4', 'Check that unique index was inherited to id_taptest_table_p200');
SELECT is_indexed('partman_test', 'id_taptest_table_p300', 'col4', 'Check that unique index was inherited to id_taptest_table_p300');
SELECT is_indexed('partman_test', 'id_taptest_table_p400', 'col4', 'Check that unique index was inherited to id_taptest_table_p400');
SELECT is_indexed('partman_test', 'id_taptest_table_default', 'col4', 'Check that unique index was inherited to id_taptest_table_default');

SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table_default', 'Check that default table has no data');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table', ARRAY[90], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p0', ARRAY[90], 'Check count from id_taptest_table_p0');

SELECT run_maintenance();
INSERT INTO partman_test.id_taptest_table (col1, col4) VALUES (generate_series(91.5,200.5), 'stuff'||generate_series(91.5,200.5));
-- Run again to make new partition based on latest data
SELECT run_maintenance();

SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table_default', 'Check that default table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p0', ARRAY[99], 'Check count from id_taptest_table_p0');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p100', ARRAY[100], 'Check count from id_taptest_table_p100');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p200', ARRAY[1], 'Check count from id_taptest_table_p200');

SELECT has_table('partman_test', 'id_taptest_table_p500', 'Check id_taptest_table_p500 exists');
SELECT hasnt_table('partman_test', 'id_taptest_table_p700', 'Check id_taptest_table_p700 doesn''t exists yet');

INSERT INTO partman_test.id_taptest_table (col1, col4) VALUES (generate_series(201.5,300.5), 'stuff'||generate_series(201.5,300.5));

SELECT run_maintenance();

SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table_default', 'Check that default table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table', ARRAY[300], 'Check count from id_taptest_table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p200', ARRAY[100], 'Check count from id_taptest_table_p200');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p300', ARRAY[1], 'Check count from id_taptest_table_p300');

SELECT has_table('partman_test', 'id_taptest_table_p700', 'Check id_taptest_table_p700 exists');
SELECT hasnt_table('partman_test', 'id_taptest_table_p800', 'Check id_taptest_table_p800 doesn''t exists yet');

INSERT INTO partman_test.id_taptest_table (col1, col4) VALUES (generate_series(2000.4,2100.4), 'stuff'||generate_series(2000.4,2100.4));
SELECT results_eq('SELECT count(*)::int FROM ONLY partman_test.id_taptest_table_default', ARRAY[101], 'Check that data outside child scope goes to default');
SELECT run_maintenance();


-- Max value is 300.5 above
SELECT drop_partition_id('partman_test.id_taptest_table', '200', p_keep_table := false);
SELECT hasnt_table('partman_test', 'id_taptest_table_p0', 'Check id_taptest_table_p0 doesn''t exists anymore');
SELECT has_table('partman_test', 'id_taptest_table_p100', 'Check id_taptest_table_p100 still exists');

UPDATE part_config SET retention = '100' WHERE parent_table = 'partman_test.id_taptest_table';
SELECT drop_partition_id('partman_test.id_taptest_table', p_keep_table := false);
SELECT hasnt_table('partman_test', 'id_taptest_table_p100', 'Check id_taptest_table_p100 doesn''t exists anymore');
SELECT has_table('partman_test', 'id_taptest_table_p200', 'Check id_taptest_table_p200 still exists');

-- Undo should remove default first if it exists and has data. Needs to run at least 2 passes to move all data
SELECT undo_partition('partman_test.id_taptest_table', 'partman_test.undo_taptest', 2, p_keep_table := false);
SELECT hasnt_table('partman_test', 'id_taptest_table_default', 'Check id_taptest_table_default does not exist');

SELECT undo_partition('partman_test.id_taptest_table', 'partman_test.undo_taptest', p_keep_table := false);
SELECT hasnt_table('partman_test', 'id_taptest_table_p200', 'Check id_taptest_table_p200 does not exist');

-- Test keeping the rest of the tables
SELECT undo_partition('partman_test.id_taptest_table', 'partman_test.undo_taptest', 10);
SELECT results_eq('SELECT count(*)::int FROM ONLY partman_test.undo_taptest', ARRAY[202], 'Check count from undo table after undo');
SELECT has_table('partman_test', 'id_taptest_table_p300', 'Check id_taptest_table_p300 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p300', 'Check child table had its data removed id_taptest_table_p300');
SELECT has_table('partman_test', 'id_taptest_table_p400', 'Check id_taptest_table_p400 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p400', 'Check child table had its data removed id_taptest_table_p400');
SELECT has_table('partman_test', 'id_taptest_table_p500', 'Check id_taptest_table_p500 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p500', 'Check child table had its data removed id_taptest_table_p500');
SELECT has_table('partman_test', 'id_taptest_table_p600', 'Check id_taptest_table_p600 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p600', 'Check child table had its data removed id_taptest_table_p600');
SELECT has_table('partman_test', 'id_taptest_table_p700', 'Check id_taptest_table_p700 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p700', 'Check child table had its data removed id_taptest_table_p700');

SELECT hasnt_table('partman_test', 'template_id_taptest_table', 'Check that template table was dropped');

DROP PUBLICATION partman_test_pub;

SELECT * FROM finish();
ROLLBACK;
