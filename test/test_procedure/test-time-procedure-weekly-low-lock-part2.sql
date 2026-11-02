\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(16);

-- Verify constraints were applied via low-lock mode and are VALID
SELECT col_has_check('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'4 weeks'::interval, 'YYYYMMDD'), 'col1'
    , 'Check for additional constraint on col1 on time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'4 weeks'::interval, 'YYYYMMDD')||' (-4 weeks)');
SELECT col_has_check('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'8 weeks'::interval, 'YYYYMMDD'), 'col1'
    , 'Check for additional constraint on col1 on time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'8 weeks'::interval, 'YYYYMMDD'));
SELECT col_has_check('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'7 weeks'::interval, 'YYYYMMDD'), 'col1'
    , 'Check for additional constraint on col1 on time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'7 weeks'::interval, 'YYYYMMDD'));
SELECT col_has_check('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'6 weeks'::interval, 'YYYYMMDD'), 'col1'
    , 'Check for additional constraint on col1 on time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'6 weeks'::interval, 'YYYYMMDD'));
SELECT col_has_check('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'5 weeks'::interval, 'YYYYMMDD'), 'col1'
    , 'Check for additional constraint on col1 on time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'5 weeks'::interval, 'YYYYMMDD'));

-- Verify constraints created by low-lock mode are VALID (convalidated = true)
SELECT results_eq(
    format('SELECT con.convalidated FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p%s'' AND con.conname LIKE ''partmanconstr_%%'' AND con.contype = ''c''',
        to_char(date_trunc('week',CURRENT_TIMESTAMP)-'8 weeks'::interval, 'YYYYMMDD')),
    ARRAY[true],
    'Check constraint is VALID on -8 weeks partition (low-lock mode should validate after adding NOT VALID)');

SELECT results_eq(
    format('SELECT con.convalidated FROM pg_constraint con JOIN pg_class c ON c.oid = con.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p%s'' AND con.conname LIKE ''partmanconstr_%%'' AND con.contype = ''c''',
        to_char(date_trunc('week',CURRENT_TIMESTAMP)-'5 weeks'::interval, 'YYYYMMDD')),
    ARRAY[true],
    'Check constraint is VALID on -5 weeks partition (low-lock mode should validate after adding NOT VALID)');

-- Cleanup
SELECT undo_partition('partman_test.time_taptest_table', 'partman_test.target_time_taptest_table', 20, p_keep_table := false);
SELECT results_eq('SELECT count(*)::int FROM partman_test.target_time_taptest_table', ARRAY[110], 'Check count from target table after undo');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP), 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP), 'YYYYMMDD')||' does not exist (now)');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'1 week'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'1 week'::interval, 'YYYYMMDD')||' does not exist (+1 weeks)');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'2 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'2 weeks'::interval, 'YYYYMMDD')||' does not exist (+2 weeks)');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'3 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'3 weeks'::interval, 'YYYYMMDD')||' does not exist (+3 weeks)');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'4 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'4 weeks'::interval, 'YYYYMMDD')||' does not exist (+4 weeks)');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'5 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'5 weeks'::interval, 'YYYYMMDD')||' does not exist (+5 weeks)');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'1 week'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'1 week'::interval, 'YYYYMMDD')||' does not exist (-1 weeks)');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'2 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'2 weeks'::interval, 'YYYYMMDD')||' does not exist (-2 weeks)');

DROP SCHEMA IF EXISTS partman_test CASCADE;

SELECT diag('!!! Final test complete !!!');

SELECT * FROM finish();
