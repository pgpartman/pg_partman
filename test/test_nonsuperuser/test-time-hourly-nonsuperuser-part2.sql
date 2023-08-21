-- ########## TIME HOURLY TESTS ##########
-- Additional tests: Testing nonsuperuser
\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true


-- NOTE: THIS FILE MUST BE RUN AS partman_basic AND CONNECT TO THE DATABASE THAT RAN PART 1 TO EFFECTIVLELY TEST AS NONSUPERUSER
--      Ex  pg_prove -ovf -U partman_basic -d mydb test/test_nonsuperuser/test-time-hourly-nonsuperuser-part2.sql

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(54);

CREATE TABLE partman_test.time_taptest_table (
    col1 serial
    , col2 text
    , col3 timestamp NOT NULL DEFAULT now()) 
    PARTITION BY RANGE (col3);
CREATE TABLE partman_test.time_taptest_undo (LIKE partman_test.time_taptest_table);

SELECT has_table('partman_test', 'time_taptest_table', 'Check that parent was created');

SELECT create_parent('partman_test.time_taptest_table', 'col3', '1 hour');
ALTER TABLE template_partman_test_time_taptest_table ADD PRIMARY KEY (col1);

UPDATE part_config SET inherit_privileges = TRUE;
SELECT reapply_privileges('partman_test.time_taptest_table');

SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), 'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(1,10), CURRENT_TIMESTAMP);

SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_default', 'Check that default table has no data');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table', ARRAY[10], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), 
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'));

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(11,20), CURRENT_TIMESTAMP + '1 hour'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(21,25), CURRENT_TIMESTAMP + '2 hours'::interval);

SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_default', 'Check that default table has no data');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table', ARRAY[25], 'Check count from time_taptest_table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    ARRAY[5], 'Check count from time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'));

UPDATE part_config SET premake = 5 WHERE parent_table = 'partman_test.time_taptest_table';
SELECT run_maintenance();
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
-- New tables should have primary keys
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'));

UPDATE part_config SET premake = 6 WHERE parent_table = 'partman_test.time_taptest_table';
SELECT run_maintenance();
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'9 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'9 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'));

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(200,210), CURRENT_TIMESTAMP + '20 hours'::interval);
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_default', ARRAY[11], 'Check that data outside scope goes to default');

-- Keep tables after undoing
SELECT undo_partition('partman_test.time_taptest_table', p_loop_count => 20, p_target_table => 'partman_test.time_taptest_undo');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');


SELECT * FROM finish();
ROLLBACK;
