-- ########## TIME HOURLY TESTS ##########
-- Additional tests: Testing RLS and nonsuperuser
\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true


-- NOTE: THIS FILE MUST BE RUN AS partman_beta AND CONNECT TO THE DATABASE THAT RAN PART 1 TO EFFECTIVLELY TEST RLS POLICY
--      Ex  pg_prove -ovf -U partman_beta -d mydb test/test_manual/rls/test-part3-rls-beta.sql

--BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(21);

CREATE TABLE partman_test.time_taptest_table_beta (
    col1 serial
    , col2 text
    , col3 timestamp NOT NULL DEFAULT now())
    PARTITION BY RANGE (col3);
CREATE TABLE partman_test.time_taptest_beta_undo (LIKE partman_test.time_taptest_table_beta);

SELECT has_table('partman_test', 'time_taptest_table_beta', 'Check that parent was created');

SELECT create_partition('partman_test.time_taptest_table_beta', 'col3', '1 hour');
ALTER TABLE template_partman_test_time_taptest_table_beta ADD PRIMARY KEY (col1);

UPDATE part_config SET inherit_privileges = TRUE;
SELECT reapply_privileges('partman_test.time_taptest_table_beta');

SELECT results_eq('SELECT count(*)::int FROM partman.part_config', ARRAY[1], 'Ensure there is only one entry from part_config returned by beta user');
SELECT is_empty('SELECT parent_table FROM partman.part_config WHERE parent_table = ''alpha''', 'Ensure alpha entry in part_config is not visible');

SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), 'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'5 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');

INSERT INTO partman_test.time_taptest_table_beta (col1, col3) VALUES (generate_series(1,10), CURRENT_TIMESTAMP);

SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_default', 'Check that default table has no data');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_beta', ARRAY[10], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'),
    ARRAY[10], 'Check count from time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'));

INSERT INTO partman_test.time_taptest_table_beta (col1, col3) VALUES (generate_series(11,20), CURRENT_TIMESTAMP + '1 hour'::interval);
INSERT INTO partman_test.time_taptest_table_beta (col1, col3) VALUES (generate_series(21,25), CURRENT_TIMESTAMP + '2 hours'::interval);

SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_default', 'Check that default table has no data');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_beta', ARRAY[25], 'Check count from time_taptest_table_beta');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'),
    ARRAY[10], 'Check count from time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'),
    ARRAY[5], 'Check count from time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'));

UPDATE part_config SET premake = 5 WHERE parent_table = 'partman_test.time_taptest_table_beta';


SELECT * FROM finish();
--ROLLBACK;
