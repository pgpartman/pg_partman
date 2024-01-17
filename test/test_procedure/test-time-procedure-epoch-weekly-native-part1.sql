-- ########## NATIVE TIME WEEKLY EPOCH TESTS ##########
-- Other tests: start_partition. Native epoch partitioning with stored procedure moving data from source

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(15);
CREATE SCHEMA partman_test;

CREATE TABLE partman_test.time_taptest_table_source (
    col1 bigint primary key
    , col2 text
    , col3 bigint);

INSERT INTO partman_test.time_taptest_table_source (col1, col3) VALUES (generate_series(1,10), extract('epoch' from date_trunc('week',CURRENT_TIMESTAMP) - '8 weeks'::interval)::int);
INSERT INTO partman_test.time_taptest_table_source (col1, col3) VALUES (generate_series(11,20), extract('epoch' from date_trunc('week',CURRENT_TIMESTAMP) - '7 weeks'::interval)::int);
INSERT INTO partman_test.time_taptest_table_source (col1, col3) VALUES (generate_series(21,25), extract('epoch' from date_trunc('week',CURRENT_TIMESTAMP) - '6 weeks'::interval)::int);
INSERT INTO partman_test.time_taptest_table_source (col1, col3) VALUES (generate_series(26,30), extract('epoch' from date_trunc('week',CURRENT_TIMESTAMP) - '5 weeks'::interval)::int);
INSERT INTO partman_test.time_taptest_table_source (col1, col3) VALUES (generate_series(31,37), extract('epoch' from date_trunc('week',CURRENT_TIMESTAMP) - '4 week'::interval)::int);
INSERT INTO partman_test.time_taptest_table_source (col1, col3) VALUES (generate_series(38,49), extract('epoch' from date_trunc('week',CURRENT_TIMESTAMP) - '3 week'::interval)::int);
INSERT INTO partman_test.time_taptest_table_source (col1, col3) VALUES (generate_series(50,70), extract('epoch' from date_trunc('week',CURRENT_TIMESTAMP) - '2 weeks'::interval)::int);
INSERT INTO partman_test.time_taptest_table_source (col1, col3) VALUES (generate_series(71,85), extract('epoch' from date_trunc('week',CURRENT_TIMESTAMP) - '1 week'::interval)::int);
INSERT INTO partman_test.time_taptest_table_source (col1, col3) VALUES (generate_series(86,100), extract('epoch' from date_trunc('week',CURRENT_TIMESTAMP) + '1 week'::interval)::int);
INSERT INTO partman_test.time_taptest_table_source (col1, col3) VALUES (generate_series(101,110), extract('epoch' from date_trunc('week',CURRENT_TIMESTAMP) + '2 weeks'::interval)::int);

CREATE TABLE partman_test.time_taptest_table_target (
    col1 bigint primary key
    , col2 text
    , col3 bigint);

CREATE TABLE partman_test.time_taptest_table (
    col1 int,
    col2 text,
    col3 bigint NOT NULL DEFAULT extract('epoch' from CURRENT_TIMESTAMP)::int)
PARTITION BY RANGE (col3);
CREATE TABLE partman_test.undo_taptest (LIKE partman_test.time_taptest_table INCLUDING ALL);

SELECT create_parent('partman_test.time_taptest_table', 'col3', '1 week', p_epoch := 'seconds'
    , p_premake := 2, p_start_partition := to_char(date_trunc('week',CURRENT_TIMESTAMP) - '8 weeks'::interval, 'YYYY-MM-DD HH24:MI:SS'));

SELECT is_partitioned('partman_test', 'time_taptest_table', 'Check that time_taptest_table is natively partitioned');


SELECT has_table('partman_test', 'time_taptest_table_default', 'Check time_taptest_table_default exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP), 'YYYYMMDD'), 'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP), 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'1 week'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'1 week'::interval, 'YYYYMMDD')||' exists (+1 weeks)');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'2 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'2 weeks'::interval, 'YYYYMMDD')||' exists (+2 weeks)');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'3 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)+'3 weeks'::interval, 'YYYYMMDD')||' does not exist (+3 weeks)');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'1 week'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'1 week'::interval, 'YYYYMMDD')||' exists (-1 weeks)');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'2 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'2 weeks'::interval, 'YYYYMMDD')||' exists (-2 weeks)');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'3 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'3 weeks'::interval, 'YYYYMMDD')||' exists (-3 weeks)');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'4 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'4 weeks'::interval, 'YYYYMMDD')||' exists (-4 weeks)');



SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'5 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'5 weeks'::interval, 'YYYYMMDD')||' exists (-5 weeks)');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'6 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'6 weeks'::interval, 'YYYYMMDD')||' exists (-6 weeks)');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'7 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'7 weeks'::interval, 'YYYYMMDD')||' exists (-7 weeks)');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'8 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'8 weeks'::interval, 'YYYYMMDD')||' exists (-8 weeks)');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'9 weeks'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_'||to_char(date_trunc('week',CURRENT_TIMESTAMP)-'9 weeks'::interval, 'YYYYMMDD')||' does not exist (-9 weeks)');

SELECT diag('!!! In separate psql terminal, please run the following (adjusting schema if needed): "CALL partman.partition_data_proc(''partman_test.time_taptest_table'', p_wait := 0, p_source_table := ''partman_test.time_taptest_table_source'');".');
SELECT diag('!!! After that, run part2 of this script to check result !!!');


SELECT * FROM finish();
