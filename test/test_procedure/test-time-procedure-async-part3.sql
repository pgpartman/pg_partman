-- ########## TIME DAILY TESTS PROCEDURE ##########
-- Other tests:
    -- test async partitioning process
    -- partition and undo with procedures instead of functions

\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(4);

-- Data that is being moved should not be visible in parent table until an entire child table has been completed
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table',
    ARRAY[85], 'Check count from parent time_taptest_table to ensure full row is missing the 6 hr block');
-- Only one six hour block should have been moved from default
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_default',
    ARRAY[61], 'Check count from time_taptest_table_default only had one six hour block removed');
-- Ensure temp storage table still exists
SELECT has_table('partman_test', 'partman_tmp_storage_time_taptest_table',
    'Check that temp storage table exists: partman_test.partman_tmp_storage_time_taptest_table');
-- Ensure count in temp storage table
SELECT results_eq('SELECT count(*)::int FROM partman_test.partman_tmp_storage_time_taptest_table',
    ARRAY[12], 'Check count from temp storage only has one 6 hr block of data');

-- Run enough loops to complete this single child table
SELECT diag('!!! In separate psql terminal, please run the following to complete a single child table (adjusting schema if needed): "CALL partman.partition_data_async(''partman_test.time_taptest_table'', p_loop_count := 6, p_interval := ''6 hours'', p_wait := 0);"');
SELECT diag('!!! After that, run part4 of this script to check result !!!');

SELECT * FROM finish();
