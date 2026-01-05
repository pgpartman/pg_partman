-- ########## TIME DAILY TESTS PROCEDURE ##########
-- Other tests:
    -- test async partitioning process
    -- partition and undo with procedures instead of functions

\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(18);
CREATE SCHEMA partman_test;

CREATE TABLE partman_test.time_taptest_table (
    col1 serial
    , col2 text
    , col3 timestamptz NOT NULL DEFAULT now()
) PARTITION BY RANGE (col3);

SELECT create_partition('partman_test.time_taptest_table', 'col3', '1 day');

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

DO $$
BEGIN
    EXECUTE 'DROP TABLE partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD');
    EXECUTE 'DROP TABLE partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 day'::interval, 'YYYYMMDD');
    EXECUTE 'DROP TABLE partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 day'::interval, 'YYYYMMDD');
    EXECUTE 'DROP TABLE partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 day'::interval, 'YYYYMMDD');
END
$$;

SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 days'::interval, 'YYYYMMDD')||' was dropped for async test');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||' was dropped for async test');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||' was dropped for async test');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||' was dropped for async test');


-- Insert for the next 4 days to test async. 24 rows per day to be able to test smaller interval movements that leave rows behind in temp table
INSERT INTO partman_test.time_taptest_table (col3) VALUES (generate_series(date_trunc('day',CURRENT_TIMESTAMP), date_trunc('day',CURRENT_TIMESTAMP + '4 days'::interval), '1 hour'::interval));

-- It makes 97 rows (96 + 1 row for midnight on 5th day). 24 rows in current day partition, 73 in the default
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table',
    ARRAY[97], 'Check count from parent time_taptest_table to ensure full row count ');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_default',
    ARRAY[73], 'Check count from time_taptest_table_default has the data to be partitioned');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'),
    ARRAY[24], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD')||' current date table');


SELECT diag('!!! In separate psql terminal, please run the following (adjusting schema if needed): "CALL partman.partition_data_async(''partman_test.time_taptest_table'', p_loop_count := 1, p_interval := ''6 hours'', p_wait := 0);"');
SELECT diag('!!! After that, run part2 of this script to check result !!!');

SELECT * FROM finish();
