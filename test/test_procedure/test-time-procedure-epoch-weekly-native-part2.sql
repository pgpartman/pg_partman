\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(12);


SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_source', 'Check that source table has had data moved to partition');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table', ARRAY[110], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP) - '8 weeks'::interval, 'YYYYMMDD'),
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'8 weeks'::interval, 'YYYYMMDD')||' (-8 weeks)');

SELECT is_empty('SELECT * FROM ONLY partman_test.time_taptest_table', 'Check that parent table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'7 weeks'::interval, 'YYYYMMDD'),
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'7 weeks'::interval, 'YYYYMMDD')||' (-7 weeks)');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'6 weeks'::interval, 'YYYYMMDD'),
    ARRAY[5], 'Check count from time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'6 weeks'::interval, 'YYYYMMDD')||' (-6 weeks)');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'5 weeks'::interval, 'YYYYMMDD'),
    ARRAY[5], 'Check count from time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'5 weeks'::interval, 'YYYYMMDD')||' (-5 weeks)');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'4 weeks'::interval, 'YYYYMMDD'),
    ARRAY[7], 'Check count from time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'4 weeks'::interval, 'YYYYMMDD')||' (-4 weeks)');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'3 weeks'::interval, 'YYYYMMDD'),
    ARRAY[12], 'Check count from time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'3 weeks'::interval, 'YYYYMMDD')||' (-3 weeks)');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'2 weeks'::interval, 'YYYYMMDD'),
    ARRAY[21], 'Check count from time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'2 weeks'::interval, 'YYYYMMDD')||' (-2 weeks)');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'1 week'::interval, 'YYYYMMDD'),
    ARRAY[15], 'Check count from time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'1 week'::interval, 'YYYYMMDD')||' (-1 weeks)');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'1 week'::interval, 'YYYYMMDD'),
    ARRAY[15], 'Check count from time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'1 week'::interval, 'YYYYMMDD')||' (+1 weeks)');

UPDATE part_config SET premake = 3 WHERE parent_table = 'partman_test.time_taptest_table';

SELECT diag('!!! In separate psql terminal, please run the following (adjusting schema if needed): "CALL partman.run_maintenance_proc();".');
SELECT diag('!!! After that, run part3 of this script to check result !!!');

SELECT * FROM finish();
