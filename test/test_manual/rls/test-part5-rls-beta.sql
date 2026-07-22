-- ########## TIME HOURLY TESTS ##########
-- Additional tests: Testing RLS and nonsuperuser
\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true


-- NOTE: THIS FILE MUST BE RUN AS partman_beta AND CONNECT TO THE DATABASE THAT RAN PART 1 TO EFFECTIVLELY TEST RLS POLICY
--      Ex  pg_prove -ovf -U partman_beta -d mydb test/test_manual/rls/test-part5-rls-beta.sql

--BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(14);

SELECT results_eq('SELECT count(*)::int FROM partman.show_partitions(''partman_test.time_taptest_table_beta'')', ARRAY[9], 'Ensure maintenance has not yet run on beta partition set');

SELECT results_eq('SELECT count(*)::int FROM partman.part_config', ARRAY[1], 'Ensure there is only one entry from part_config returned by alpha user');
SELECT is_empty('SELECT parent_table FROM partman.part_config WHERE parent_table = ''alpha''', 'Ensure alpha entry in part_config is not visible');

SELECT run_maintenance();
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
-- New tables should have primary keys
SELECT col_is_pk('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'));

UPDATE part_config SET premake = 6 WHERE parent_table = 'partman_test.time_taptest_table_beta';
SELECT run_maintenance();
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'9 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'9 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT col_is_pk('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'));

INSERT INTO partman_test.time_taptest_table_beta (col1, col3) VALUES (generate_series(200,210), CURRENT_TIMESTAMP + '20 hours'::interval);
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_beta_default', ARRAY[11], 'Check that data outside scope goes to default');

SELECT * FROM finish();
--ROLLBACK;
