-- Additional tests: Testing nonsuperuser

-- NOTE: THIS FILE MUST BE RUN AS partman_beta AND CONNECT TO THE DATABASE THAT RAN PART 1 TO EFFECTIVLELY TEST RLS POLICY
--      Ex  pg_prove -ovf -U partman_beta -d mydb test/test_manual/rls/test-part7-rls-beta.sql

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(24);

-- Keep tables after undoing
SELECT undo_partition('partman_test.time_taptest_table_beta', p_loop_count => 20, p_target_table => 'partman_test.time_taptest_beta_undo');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'),
    'Check time_taptest_table_beta_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');

SELECT * FROM finish();
