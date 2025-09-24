-- ########## TIME DAILY TESTS PROCEDURE ##########
-- Other tests:
    -- test async partitioning process
    -- partition and undo with procedures instead of functions

\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(4);

-- Data that is being moved should not be visible in parent table until an entire child table has been completed
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table',
    ARRAY[91], 'Check count from parent time_taptest_table to ensure full row is missing the 6 hr block');
-- Only one six hour block should have been moved from default
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_default',
    ARRAY[67], 'Check count from time_taptest_table_default only had one six hour block removed');
-- Ensure temp storage table still exists
SELECT has_table('partman_test', 'partman_tmp_storage_time_taptest_table',
    'Check that temp storage table exists: partman_test.partman_tmp_storage_time_taptest_table');
-- Ensure count in temp storage table
SELECT results_eq('SELECT count(*)::int FROM partman_test.partman_tmp_storage_time_taptest_table',
    ARRAY[6], 'Check count from temp storage only has one 6 hr block of data');

-- Run another single 6 hour block and to check again
SELECT diag('!!! In separate psql terminal, please run the following (adjusting schema if needed): "CALL partman.partition_data_async(''partman_test.time_taptest_table'', p_loop_count := 1, p_interval := ''6 hours'', p_wait := 0);"');
SELECT diag('!!! After that, run part3 of this script to check result !!!');

SELECT * FROM finish();
