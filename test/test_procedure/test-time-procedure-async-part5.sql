-- ########## TIME DAILY TESTS PROCEDURE ##########
-- Other tests:
    -- test async partitioning process
    -- partition and undo with procedures instead of functions

\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(6);

-- Ensure temp storage table has been removed
SELECT hasnt_table('partman', 'partman_tmp_storage_partman_test_time_taptest_table',
    'Check that temp storage table was dropped: partman.partman_tmp_storage_partman_test_time_taptest_table');

SELECT is_empty('SELECT * FROM ONLY partman_test.time_taptest_table_default', 'Check that default is now empty');

SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 day'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 day'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 day'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 day'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 day'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 day'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' does not exist yet');


CREATE TABLE partman_test.undo_taptest (LIKE partman_test.time_taptest_table INCLUDING ALL);

SELECT diag('!!! In separate psql terminal, please run the following (adjusting schema if needed): "CALL partman.undo_partition_proc(''partman_test.time_taptest_table'', p_target_table := ''partman_test.undo_taptest'', p_loop_count := 20, p_interval := ''6 hours'', p_wait := 0, p_keep_table := false );"');
SELECT diag('!!! After that, run part6 of this script to check result !!!');

SELECT * FROM finish();
