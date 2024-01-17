-- ########## TIME DAILY TESTS ##########
-- Other tests: 
    -- Test generated always columns

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(84);

CREATE SCHEMA partman_test;

CREATE TABLE partman_test.time_taptest_table (
    col1 int
    , col2 text default 'stuff'
    , col3 timestamptz NOT NULL DEFAULT now()
    , col4 bigint GENERATED ALWAYS AS (col1 * 100) STORED ) 
    PARTITION BY RANGE (col3);
CREATE TABLE partman_test.undo_taptest (LIKE partman_test.time_taptest_table INCLUDING ALL);

SELECT create_parent('partman_test.time_taptest_table', 'col3', '1 day');

SELECT is_partitioned('partman_test', 'time_taptest_table', 'Check that time_taptest_table is natively partitioned');
SELECT has_table('partman', 'template_partman_test_time_taptest_table', 'Check that default template table was created');

-- Add inheritable stuff to template table
ALTER TABLE template_partman_test_time_taptest_table ADD PRIMARY KEY (col1);

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(1,10), CURRENT_TIMESTAMP);

SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'5 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'5 days'::interval, 'YYYYMMDD')||' does not exist');

SELECT col_isnt_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for NO primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT col_isnt_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for NO primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for NO primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for NO primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for NO primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for NO primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT col_isnt_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for NO primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for NO primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for NO primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for NO primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'));

SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_default', 'Check that default table is empty.');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table', ARRAY[10], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));

SELECT results_eq('SELECT col4::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 
    ARRAY[100,200,300,400,500,600,700,800,900,1000], 'Check generated values from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(11,20), CURRENT_TIMESTAMP + '1 day'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(21,25), CURRENT_TIMESTAMP + '2 days'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(26,30), CURRENT_TIMESTAMP + '3 days'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(31,37), CURRENT_TIMESTAMP + '4 days'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(40,49), CURRENT_TIMESTAMP - '1 day'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(50,70), CURRENT_TIMESTAMP - '2 days'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(71,85), CURRENT_TIMESTAMP - '3 days'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(86,100), CURRENT_TIMESTAMP - '4 days'::interval);

SELECT is_empty('SELECT * FROM ONLY partman_test.time_taptest_table_default', 'Check that default table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 
    ARRAY[5], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 
    ARRAY[5], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 
    ARRAY[7], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 
    ARRAY[21], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 
    ARRAY[15], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 
    ARRAY[15], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'));

SELECT results_eq('SELECT col4::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 
    ARRAY[1100,1200,1300,1400,1500,1600,1700,1800,1900,2000], 'Check generated values from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT col4::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 day'::interval, 'YYYYMMDD'), 
    ARRAY[2100,2200,2300,2400,2500], 'Check generated values from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 day'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT col4::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 day'::interval, 'YYYYMMDD'), 
    ARRAY[2600,2700,2800,2900,3000], 'Check generated values from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 day'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT col4::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 day'::interval, 'YYYYMMDD'), 
    ARRAY[3100,3200,3300,3400,3500,3600,3700], 'Check generated values from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 day'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT col4::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 
    ARRAY[4000,4100,4200,4300,4400,4500,4600,4700,4800,4900], 'Check generated values from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));

UPDATE part_config SET premake = 5 WHERE parent_table = 'partman_test.time_taptest_table';

-- Run to create proper future partitions
SELECT run_maintenance();
-- Insert after maintenance since native fails with no child
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(101,112), CURRENT_TIMESTAMP + '5 days'::interval);
-- Run again to create +5 partition now that data exists
SELECT run_maintenance();

-- Data exists for +5 days, with 5 premake so +10 day table should exist
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD')||' does not exist');

SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'));

SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_default', 'Check that default table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 
    ARRAY[12], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));

SELECT results_eq('SELECT col4::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 
    ARRAY[10100,10200,10300,10400,10500,10600,10700,10800,10900,11000,11100,11200], 'Check generated values from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));

-- Check default and migration of data from default when using generated columns

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(120,125), CURRENT_TIMESTAMP + '11 days'::interval);

SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_default', 
    ARRAY[6], 'Check count from time_taptest_table_default');
SELECT results_eq('SELECT col4::int FROM partman_test.time_taptest_table_default', 
    ARRAY[12000,12100,12200,12300,12400,12500], 'Check generated values from time_taptest_table_default');

SELECT partition_data_time('partman_test.time_taptest_table', 10, p_ignored_columns := ARRAY['col4']);

SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD')||' was created by partition_data_time');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_default', 'Check that default had data removed');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 
    ARRAY[6], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT col4::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 
    ARRAY[12000,12100,12200,12300,12400,12500], 'Check generated values were properly moved to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'));


-- Begin undo section
SELECT drop_partition_time('partman_test.time_taptest_table', '3 days', p_keep_table := false);
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD')||' does not exist');

UPDATE part_config SET retention = '2 days'::interval WHERE parent_table = 'partman_test.time_taptest_table';
SELECT drop_partition_time('partman_test.time_taptest_table', p_keep_table := false);
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD')||' does not exist');

SELECT undo_partition('partman_test.time_taptest_table', p_loop_count => 20, p_target_table => 'partman_test.undo_taptest', p_keep_table => false, p_ignored_columns => ARRAY['col4']);
SELECT results_eq('SELECT count(*)::int FROM  partman_test.undo_taptest', ARRAY[86], 'Check count from target table after undo');

SELECT results_eq('SELECT col4::int FROM partman_test.undo_taptest ORDER BY col4 ASC LIMIT 10', ARRAY[100,200,300,400,500,600,700,800,900,1000], 'Check generated values in target table after undo (asc)');
SELECT results_eq('SELECT col4::int FROM partman_test.undo_taptest ORDER BY col4 DESC LIMIT 10', ARRAY[12500,12400,12300,12200,12100,12000,11200,11100,11000,10900], 'Check generated values in target table after undo (desc)');

SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')||' does not exist');

SELECT hasnt_table('partman', 'template_partman_test_time_taptest_table', 'Check that template table was dropped');


SELECT * FROM finish();
ROLLBACK;

