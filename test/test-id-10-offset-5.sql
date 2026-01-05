-- ########## ID 10 TESTS ##########
-- Additional tests:
    -- offset 5
    -- Test alias for create_parent
    -- pre-created template table and passing to create_parent. Should allow indexes to be made for initial children.
    -- Since this is id partitioning, we can use the partition key for primary key, so that should work from parent

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(60);
CREATE SCHEMA partman_test;
CREATE SCHEMA partman_retention_test;


CREATE TABLE partman_test.id_taptest_table
    (col1 bigint PRIMARY KEY
        , col2 text not null default 'stuff'
        , col3 timestamptz DEFAULT now()
        , col4 text )
    PARTITION BY RANGE (col1);
CREATE TABLE partman_test.undo_taptest (LIKE partman_test.id_taptest_table INCLUDING ALL);
-- Template table
CREATE TABLE partman_test.template_id_taptest_table (LIKE partman_test.id_taptest_table);

CREATE INDEX ON partman_test.id_taptest_table (col3);

-- Regular unique indexes do not work on native if the partition key isn't included
CREATE UNIQUE INDEX ON partman_test.template_id_taptest_table (col4);

SELECT create_parent('partman_test.id_taptest_table', 'col1', '10', p_offset_id := 5, p_template_table := 'partman_test.template_id_taptest_table');
UPDATE part_config SET inherit_privileges = TRUE;
SELECT reapply_privileges('partman_test.id_taptest_table');

INSERT INTO partman_test.id_taptest_table (col1, col4) VALUES (generate_series(01,09), 'stuff'||generate_series(01,09));

SELECT hasnt_table('partman_test', 'id_taptest_table_p0', 'Check id_taptest_table_p0 doesn''t exists yet');
SELECT has_table('partman_test', 'id_taptest_table_p5', 'Check id_taptest_table_p5 exists');
SELECT has_table('partman_test', 'id_taptest_table_p15', 'Check id_taptest_table_p15 exists');
SELECT has_table('partman_test', 'id_taptest_table_p25', 'Check id_taptest_table_p25 exists');
SELECT has_table('partman_test', 'id_taptest_table_p35', 'Check id_taptest_table_p35 exists');
SELECT has_table('partman_test', 'id_taptest_table_p45', 'Check id_taptest_table_p45 exists');
SELECT has_table('partman_test', 'id_taptest_table_default', 'Check id_taptest_table_default exists');
SELECT hasnt_table('partman_test', 'id_taptest_table_p55', 'Check id_taptest_table_p50 doesn''t exists yet');
SELECT col_is_pk('partman_test', 'id_taptest_table_p5', ARRAY['col1'], 'Check for primary key in id_taptest_table_p5');
SELECT col_is_pk('partman_test', 'id_taptest_table_p15', ARRAY['col1'], 'Check for primary key in id_taptest_table_p15');
SELECT col_is_pk('partman_test', 'id_taptest_table_p25', ARRAY['col1'], 'Check for primary key in id_taptest_table_p25');
SELECT col_is_pk('partman_test', 'id_taptest_table_p35', ARRAY['col1'], 'Check for primary key in id_taptest_table_p35');
SELECT col_is_pk('partman_test', 'id_taptest_table_p45', ARRAY['col1'], 'Check for primary key in id_taptest_table_p45');
SELECT col_is_pk('partman_test', 'id_taptest_table_default', ARRAY['col1'], 'Check for primary key in id_taptest_table_default');
SELECT is_indexed('partman_test', 'id_taptest_table_p5', 'col4', 'Check that unique index was inherited to id_taptest_table_p5');
SELECT is_indexed('partman_test', 'id_taptest_table_p15', 'col4', 'Check that unique index was inherited to id_taptest_table_p15');
SELECT is_indexed('partman_test', 'id_taptest_table_p25', 'col4', 'Check that unique index was inherited to id_taptest_table_p25');
SELECT is_indexed('partman_test', 'id_taptest_table_p35', 'col4', 'Check that unique index was inherited to id_taptest_table_p35');
SELECT is_indexed('partman_test', 'id_taptest_table_p45', 'col4', 'Check that unique index was inherited to id_taptest_table_p45');
SELECT is_indexed('partman_test', 'id_taptest_table_default', 'col4', 'Check that unique index was inherited to id_taptest_table_default');

SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_default', ARRAY[4], 'Check count from default (values below 5)');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table', ARRAY[9], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p5', ARRAY[5], 'Check count from id_taptest_table_p5');

DELETE FROM partman_test.id_taptest_table_default;

SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table_default', 'Check that default table has no data anymore');


SELECT run_maintenance();
INSERT INTO partman_test.id_taptest_table (col1, col4) VALUES (generate_series(10,25), 'stuff'||generate_series(10,25));
-- Run again to make new partition based on latest data
SELECT run_maintenance();

SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table_default', 'Check that default table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p15', ARRAY[10], 'Check count from id_taptest_table_p15');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p25', ARRAY[1], 'Check count from id_taptest_table_p25');

SELECT has_table('partman_test', 'id_taptest_table_p55', 'Check id_taptest_table_p55 exists');
SELECT has_table('partman_test', 'id_taptest_table_p65', 'Check id_taptest_table_p60 exists yet');
SELECT hasnt_table('partman_test', 'id_taptest_table_p75', 'Check id_taptest_table_p70 doesn''t exists yet');
SELECT col_is_pk('partman_test', 'id_taptest_table_p55', ARRAY['col1'], 'Check for primary key in id_taptest_table_p55');
SELECT col_is_pk('partman_test', 'id_taptest_table_p65', ARRAY['col1'], 'Check for primary key in id_taptest_table_p65');

INSERT INTO partman_test.id_taptest_table (col1, col4) VALUES (generate_series(26,38), 'stuff'||generate_series(26,38));

SELECT run_maintenance();

SELECT is_empty('SELECT * FROM ONLY partman_test.id_taptest_table_default', 'Check that default table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table', ARRAY[34], 'Check count from id_taptest_table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p25', ARRAY[10], 'Check count from id_taptest_table_p25');
SELECT results_eq('SELECT count(*)::int FROM partman_test.id_taptest_table_p35', ARRAY[4], 'Check count from id_taptest_table_p35');

SELECT has_table('partman_test', 'id_taptest_table_p75', 'Check id_taptest_table_p75 exists');
SELECT hasnt_table('partman_test', 'id_taptest_table_p85', 'Check id_taptest_table_p85 doesn''t exists yet');
SELECT col_is_pk('partman_test', 'id_taptest_table_p65', ARRAY['col1'], 'Check for primary key in id_taptest_table_p65');
SELECT col_is_pk('partman_test', 'id_taptest_table_p75', ARRAY['col1'], 'Check for primary key in id_taptest_table_p75');

INSERT INTO partman_test.id_taptest_table (col1, col4) VALUES (generate_series(200,210), 'stuff'||generate_series(200,210));
SELECT results_eq('SELECT count(*)::int FROM ONLY partman_test.id_taptest_table_default', ARRAY[11], 'Check that data outside child scope goes to default');
SELECT run_maintenance();

-- Max value is 38 above
SELECT drop_partition_id('partman_test.id_taptest_table', '20', p_keep_table := false);
SELECT hasnt_table('partman_test', 'id_taptest_table_p5', 'Check id_taptest_table_p5 doesn''t exists anymore');
SELECT has_table('partman_test', 'id_taptest_table_p15', 'Check id_taptest_table_p15 still exists');

UPDATE part_config SET retention = '10' WHERE parent_table = 'partman_test.id_taptest_table';
SELECT drop_partition_id('partman_test.id_taptest_table', p_retention_schema := 'partman_retention_test');
SELECT hasnt_table('partman_test', 'id_taptest_table_p15', 'Check id_taptest_table_p15 doesn''t exists anymore');
SELECT has_table('partman_retention_test', 'id_taptest_table_p15', 'Check id_taptest_table_p15 got moved to new schema');

-- Undo will remove default first if it exists and has data
SELECT undo_partition('partman_test.id_taptest_table', 'partman_test.undo_taptest', p_keep_table := false);
SELECT hasnt_table('partman_test', 'id_taptest_table_default', 'Check id_taptest_table_default does not exist');

SELECT undo_partition('partman_test.id_taptest_table', 'partman_test.undo_taptest', p_keep_table := false);
SELECT hasnt_table('partman_test', 'id_taptest_table_p25', 'Check id_taptest_table_p25 does not exist');
SELECT has_table('partman_test', 'id_taptest_table_p35', 'Check id_taptest_table_p35 still exists');

-- Test keeping the rest of the tables
SELECT undo_partition('partman_test.id_taptest_table', 'partman_test.undo_taptest', 10);
SELECT results_eq('SELECT count(*)::int FROM ONLY partman_test.undo_taptest', ARRAY[25], 'Check count from undo table after undo');
SELECT has_table('partman_test', 'id_taptest_table_p35', 'Check id_taptest_table_p35 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p35', 'Check child table had its data removed id_taptest_table_p35');
SELECT has_table('partman_test', 'id_taptest_table_p45', 'Check id_taptest_table_p45 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p45', 'Check child table had its data removed id_taptest_table_p40');
SELECT has_table('partman_test', 'id_taptest_table_p55', 'Check id_taptest_table_p55 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p55', 'Check child table had its data removed id_taptest_table_p50');
SELECT has_table('partman_test', 'id_taptest_table_p65', 'Check id_taptest_table_p65 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p65', 'Check child table had its data removed id_taptest_table_p60');
SELECT has_table('partman_test', 'id_taptest_table_p75', 'Check id_taptest_table_p75 still exists');
SELECT is_empty('SELECT * FROM partman_test.id_taptest_table_p75', 'Check child table had its data removed id_taptest_table_p70');

SELECT hasnt_table('partman_test', 'template_id_taptest_table', 'Check that template table was dropped');

SELECT * FROM finish();
ROLLBACK;
