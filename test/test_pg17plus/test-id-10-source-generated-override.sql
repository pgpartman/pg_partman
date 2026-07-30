-- ########## ID 10 TESTS ##########
-- Additional tests:
    -- Partition col is primary key with generated identity
        -- Scenario where user wants to keep the original generated values from the source table.
        -- In this case, to fully test this the generated identity will need to have its value reset (TODO)
    -- Populate initial data from source table
    -- Since this is id partitioning, we can use the partition key for primary key, so that should work from parent

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(18);
CREATE SCHEMA partman_test;
CREATE SCHEMA partman_source;

CREATE TABLE partman_test.id_taptest_table
    (col1 bigint PRIMARY KEY NOT NULL GENERATED ALWAYS AS IDENTITY
        , col2 text not null default 'stuff'
        , col3 timestamptz DEFAULT now()
        , col4 text)
    PARTITION BY RANGE (col1);
CREATE TABLE partman_test.undo_taptest (LIKE partman_test.id_taptest_table INCLUDING ALL);

CREATE TABLE partman_source.id_taptest_table_source (LIKE partman_test.id_taptest_table INCLUDING ALL);

INSERT INTO partman_source.id_taptest_table_source (col4) VALUES ('stuff'||generate_series(3000000001,3000000009));

SELECT results_eq('SELECT count(*)::int FROM partman_source.id_taptest_table_source', ARRAY[9], 'Ensure source has expected row count');

SELECT create_partition('partman_test.id_taptest_table', 'col1', '10');

SELECT has_table('partman_test', 'id_taptest_table_p0', 'Check id_taptest_table_p0 exists');
SELECT has_table('partman_test', 'id_taptest_table_p10', 'Check id_taptest_table_p10 exists');
SELECT has_table('partman_test', 'id_taptest_table_p20', 'Check id_taptest_table_p20 exists');
SELECT has_table('partman_test', 'id_taptest_table_p30', 'Check id_taptest_table_p30 exists');
SELECT has_table('partman_test', 'id_taptest_table_p40', 'Check id_taptest_table_p40 exists');
SELECT has_table('partman_test', 'id_taptest_table_default', 'Check id_taptest_table_default exists');
SELECT hasnt_table('partman_test', 'id_taptest_table_p50', 'Check id_taptest_table_p50 doesn''t exists yet');
SELECT col_is_pk('partman_test', 'id_taptest_table_p0', ARRAY['col1'], 'Check for primary key in id_taptest_table_p0');
SELECT col_is_pk('partman_test', 'id_taptest_table_p10', ARRAY['col1'], 'Check for primary key in id_taptest_table_p10');
SELECT col_is_pk('partman_test', 'id_taptest_table_p20', ARRAY['col1'], 'Check for primary key in id_taptest_table_p20');
SELECT col_is_pk('partman_test', 'id_taptest_table_p30', ARRAY['col1'], 'Check for primary key in id_taptest_table_p30');
SELECT col_is_pk('partman_test', 'id_taptest_table_p40', ARRAY['col1'], 'Check for primary key in id_taptest_table_p40');
SELECT col_is_pk('partman_test', 'id_taptest_table_default', ARRAY['col1'], 'Check for primary key in id_taptest_table_default');

SELECT results_eq('SELECT partman.partition_data_id(''partman_test.id_taptest_table'', ''20'', p_source_table := ''partman_source.id_taptest_table_source'', p_override_system_value := true, p_order := ''DESC'')::int', ARRAY[9], 'Move data out of source table into partitioned table');

SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table_default', 'Check that default table has no data');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table', ARRAY[9], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p0', ARRAY[9], 'Check count from id_taptest_table_p0');

/*
TODO Need to reset the generated key value to current value in table
For now this tests the override as intende

INSERT INTO partman_test.id_taptest_table (col4) VALUES ('stuff'||generate_series(3000000010,3000000025));
-- Run again to make new partition based on latest data
SELECT run_maintenance();

SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table', 'Check that parent table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p10', ARRAY[10], 'Check count from id_taptest_table_p10');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p20', ARRAY[6], 'Check count from id_taptest_table_p20');

SELECT has_table('partman_test', 'id_taptest_table_p50', 'Check id_taptest_table_p50 exists');
SELECT has_table('partman_test', 'id_taptest_table_p60', 'Check id_taptest_table_p60 exists yet');
SELECT hasnt_table('partman_test', 'id_taptest_table_p70', 'Check id_taptest_table_p70 doesn''t exists yet');
SELECT col_is_pk('partman_test', 'id_taptest_table_p50', ARRAY['col1'], 'Check for primary key in id_taptest_table_p50');

INSERT INTO partman_test.id_taptest_table (col4) VALUES ('stuff'||generate_series(3000000026,3000000038));

SELECT run_maintenance();

SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table', 'Check that parent table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table', ARRAY[38], 'Check count from id_taptest_table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p20', ARRAY[10], 'Check count from id_taptest_table_p20');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p30', ARRAY[9], 'Check count from id_taptest_table_p30');

SELECT has_table('partman_test', 'id_taptest_table_p70', 'Check id_taptest_table_p70 exists');
SELECT hasnt_table('partman_test', 'id_taptest_table_p80', 'Check id_taptest_table_p80 doesn''t exists yet');
SELECT col_is_pk('partman_test', 'id_taptest_table_p60', ARRAY['col1'], 'Check for primary key in id_taptest_table_p60');
SELECT col_is_pk('partman_test', 'id_taptest_table_p70', ARRAY['col1'], 'Check for primary key in id_taptest_table_p70');

-- Max value is 38 above
SELECT drop_partition_id('partman_test.id_taptest_table', '20', p_keep_table := false);
SELECT hasnt_table('partman_test', 'id_taptest_table_p0', 'Check id_taptest_table_p0 doesn''t exists anymore');
SELECT has_table('partman_test', 'id_taptest_table_p10', 'Check id_taptest_table_p10 exists');

UPDATE part_config SET retention = '10' WHERE parent_table = 'partman_test.id_taptest_table';
SELECT drop_partition_id('partman_test.id_taptest_table', p_keep_table := false);
SELECT hasnt_table('partman_test', 'id_taptest_table_p10', 'Check id_taptest_table_p10 doesn''t exists anymore');
SELECT has_table('partman_test', 'id_taptest_table_p20', 'Check id_taptest_table_p20 exists');

SELECT undo_partition('partman_test.id_taptest_table', 'partman_test.undo_taptest', p_keep_table := false, p_ignored_columns := ARRAY['col1']);
SELECT hasnt_table('partman_test', 'id_taptest_table_p20', 'Check id_taptest_table_p20 does not exist');
SELECT has_table('partman_test', 'id_taptest_table_p30', 'Check id_taptest_table_p30 exists');

-- Test keeping the rest of the tables
SELECT undo_partition('partman_test.id_taptest_table', 'partman_test.undo_taptest', 10, p_ignored_columns := ARRAY['col1']);
SELECT results_eq('SELECT count(*)::int FROM ONLY partman_test.undo_taptest', ARRAY[19], 'Check count from undo table after undo');
SELECT has_table('partman_test', 'id_taptest_table_p30', 'Check id_taptest_table_p30 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p30', 'Check child table had its data removed id_taptest_table_p30');
SELECT has_table('partman_test', 'id_taptest_table_p40', 'Check id_taptest_table_p40 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p40', 'Check child table had its data removed id_taptest_table_p40');
SELECT has_table('partman_test', 'id_taptest_table_p50', 'Check id_taptest_table_p50 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p50', 'Check child table had its data removed id_taptest_table_p50');
SELECT has_table('partman_test', 'id_taptest_table_p60', 'Check id_taptest_table_p60 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p60', 'Check child table had its data removed id_taptest_table_p60');
SELECT has_table('partman_test', 'id_taptest_table_p70', 'Check id_taptest_table_p70 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p70', 'Check child table had its data removed id_taptest_table_p70');

SELECT hasnt_table('partman_test', 'template_id_taptest_table', 'Check that template table was dropped');
*/
SELECT * FROM finish();
ROLLBACK;
