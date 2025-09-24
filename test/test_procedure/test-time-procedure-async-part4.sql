-- ########## TIME DAILY TESTS PROCEDURE ##########
-- Other tests:
    -- test async partitioning process
    -- partition and undo with procedures instead of functions

\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(5);

-- Ensure temp storage table has been removed
SELECT hasnt_table('partman', 'partman_tmp_storage_partman_test_time_taptest_table',
    'Check that temp storage table was dropped: partman.partman_tmp_storage_partman_test_time_taptest_table');

-- Check that original data visibility from parent has been restored
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table',
    ARRAY[97], 'Check count from parent time_taptest_table to ensure data was moved properly');
-- Ensure 24 hour block of data was removed from default
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_default',
    ARRAY[49], 'Check count from time_taptest_table_default had 1 day removed');
-- Ensure only one new child table was made
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||' does not exist yet');


-- Partition the remaining data using the 6 hour interval
SELECT diag('!!! In separate psql terminal, please run the following (adjusting schema if needed): "CALL partman.partition_data_async(''partman_test.time_taptest_table'', p_interval := ''6 hours'', p_wait := 0);"');
SELECT diag('!!! After that, run part5 of this script to check result !!!');

SELECT * FROM finish();

/*
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table', ARRAY[10], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'),
    ARRAY[1], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));

SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'9 day'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'9 day'::interval, 'YYYYMMDD')||' exists');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'9 days'::interval, 'YYYYMMDD'),
    ARRAY[1], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'9 days'::interval, 'YYYYMMDD'));
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'5 day'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'5 day'::interval, 'YYYYMMDD')||' exists');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'5 days'::interval, 'YYYYMMDD'),
    ARRAY[1], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'5 days'::interval, 'YYYYMMDD'));
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'10 day'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'10 day'::interval, 'YYYYMMDD')||' does not exist');

INSERT INTO partman_test.time_taptest_table (col3) VALUES (CURRENT_TIMESTAMP + '1 day'::interval);
INSERT INTO partman_test.time_taptest_table (col3) VALUES (CURRENT_TIMESTAMP + '2 days'::interval);
INSERT INTO partman_test.time_taptest_table (col3) VALUES (CURRENT_TIMESTAMP + '3 days'::interval);
INSERT INTO partman_test.time_taptest_table (col3) VALUES (CURRENT_TIMESTAMP + '4 days'::interval);


SELECT is_empty('SELECT * FROM ONLY partman_test.time_taptest_table', 'Check that parent table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'),
    ARRAY[1], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'),
    ARRAY[1], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'),
    ARRAY[1], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'),
    ARRAY[1], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));

UPDATE part_config SET premake = 5 WHERE parent_table = 'partman_test.time_taptest_table';
-- Run maintenance to create new +5 day table
SELECT run_maintenance(p_analyze := false);
-- Insert after maintenance so data goes to new +5 day table
INSERT INTO partman_test.time_taptest_table (col3) VALUES (CURRENT_TIMESTAMP + '5 days'::interval);
-- Run again to create proper future partitions
SELECT run_maintenance(p_analyze := false);

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


SELECT is_empty('SELECT * FROM ONLY partman_test.time_taptest_table', 'Check that parent table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'),
    ARRAY[1], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));

SELECT diag('!!! In separate psql terminal, please run the following (adjusting schema if needed): "CALL partman.undo_partition_proc(''partman_test.time_taptest_table'', p_keep_table := false, p_target_table := ''partman_test.time_taptest_table_target'', p_wait := 0);".');
SELECT diag('!!! After that, run part3 of this script to check result and cleanup testing !!!');
*/
