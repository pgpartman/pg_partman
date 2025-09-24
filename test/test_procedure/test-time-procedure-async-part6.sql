-- ########## TIME DAILY TESTS PROCEDURE ##########
-- Other tests:
    -- test async partitioning process
    -- partition and undo with procedures instead of functions

\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(15);

-- Ensure temp storage table has been removed
SELECT hasnt_table('partman', 'partman_tmp_storage_partman_test_time_taptest_table',
    'Check that temp storage table is still gone: partman.partman_tmp_storage_partman_test_time_taptest_table');

SELECT hasnt_table('partman_test', 'time_taptest_table_default', 'Check time_taptest_table_default does not exist');

SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' does not exist');

DROP SCHEMA IF EXISTS partman_test CASCADE;

SELECT hasnt_table('partman_test', 'time_taptest_table', 'Check time_taptest_table does not exist');
SELECT hasnt_table('partman_test', 'undo_taptest', 'Check undo_taptest does not exist');
SELECT hasnt_schema('partman_test', 'Check schema partman_test does not exist');

SELECT diag('!!! Final test complete !!!');

SELECT * FROM finish();
