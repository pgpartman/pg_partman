-- ########## TIME MONTHLY, ROWS ON A CHILD TABLE'S BOUNDARIES ##########
-- Other tests:
    -- partition_data_time() moves a row on the first instant of a month into that month, and leaves
    --      a row on the first instant of the next month out of it
    -- date control column, out of the default and out of a source table (Github Issue #856)
    -- timestamp without time zone control column (Github Issue #838)

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(12);
CREATE SCHEMA partman_test;

CREATE TABLE partman_test.time_taptest_table
    (col1 int
     , col2 text
     , col3 date NOT NULL)
    PARTITION BY RANGE (col3);

SELECT create_partition('partman_test.time_taptest_table', 'col3', '1 month', p_start_partition := to_char(date_trunc('month', CURRENT_DATE), 'YYYY-MM-DD'));

-- First, middle and last day of the month three months back, and the first day of the month after it.
-- No child table covers either month yet, so all four rows go to the default.
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES
    (1, date_trunc('month', CURRENT_DATE - '3 months'::interval)::date)
    , (2, date_trunc('month', CURRENT_DATE - '3 months'::interval)::date + 14)
    , (3, date_trunc('month', CURRENT_DATE - '2 months'::interval)::date - 1)
    , (4, date_trunc('month', CURRENT_DATE - '2 months'::interval)::date);

SELECT results_eq('SELECT partition_data_time(''partman_test.time_taptest_table''::text, p_batch_count := 2)::int', ARRAY[4], 'Check that partition_data_time moves all four rows out of the default');
SELECT is_empty('SELECT * FROM ONLY partman_test.time_taptest_table_default', 'Check that the default is empty');
SELECT results_eq('SELECT col1 FROM partman_test.time_taptest_table_p'||to_char(date_trunc('month', CURRENT_DATE - '3 months'::interval), 'YYYYMMDD')||' ORDER BY col1',
    ARRAY[1, 2, 3], 'Check that time_taptest_table_p'||to_char(date_trunc('month', CURRENT_DATE - '3 months'::interval), 'YYYYMMDD')||' holds its first, middle and last day');
SELECT results_eq('SELECT col1 FROM partman_test.time_taptest_table_p'||to_char(date_trunc('month', CURRENT_DATE - '2 months'::interval), 'YYYYMMDD')||' ORDER BY col1',
    ARRAY[4], 'Check that time_taptest_table_p'||to_char(date_trunc('month', CURRENT_DATE - '2 months'::interval), 'YYYYMMDD')||' holds its first day');

-- The same four days, six and five months back, out of a source table
CREATE TABLE partman_test.time_taptest_source (col1 int, col2 text, col3 date NOT NULL);
INSERT INTO partman_test.time_taptest_source (col1, col3) VALUES
    (5, date_trunc('month', CURRENT_DATE - '6 months'::interval)::date)
    , (6, date_trunc('month', CURRENT_DATE - '6 months'::interval)::date + 14)
    , (7, date_trunc('month', CURRENT_DATE - '5 months'::interval)::date - 1)
    , (8, date_trunc('month', CURRENT_DATE - '5 months'::interval)::date);

SELECT results_eq('SELECT partition_data_time(''partman_test.time_taptest_table''::text, p_batch_count := 2, p_source_table := ''partman_test.time_taptest_source'')::int',
    ARRAY[4], 'Check that partition_data_time moves all four rows out of the source table');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_source', 'Check that the source table is empty');
SELECT results_eq('SELECT col1 FROM partman_test.time_taptest_table_p'||to_char(date_trunc('month', CURRENT_DATE - '6 months'::interval), 'YYYYMMDD')||' ORDER BY col1',
    ARRAY[5, 6, 7], 'Check that time_taptest_table_p'||to_char(date_trunc('month', CURRENT_DATE - '6 months'::interval), 'YYYYMMDD')||' holds its first, middle and last day');
SELECT results_eq('SELECT col1 FROM partman_test.time_taptest_table_p'||to_char(date_trunc('month', CURRENT_DATE - '5 months'::interval), 'YYYYMMDD')||' ORDER BY col1',
    ARRAY[8], 'Check that time_taptest_table_p'||to_char(date_trunc('month', CURRENT_DATE - '5 months'::interval), 'YYYYMMDD')||' holds its first day');

-- A timestamp without time zone control column, with rows on the first and last second of a month
CREATE TABLE partman_test.time_taptest_timestamp
    (col1 int
     , col2 text
     , col3 timestamp NOT NULL)
    PARTITION BY RANGE (col3);

SELECT create_partition('partman_test.time_taptest_timestamp', 'col3', '1 month', p_start_partition := to_char(date_trunc('month', CURRENT_DATE), 'YYYY-MM-DD'));

INSERT INTO partman_test.time_taptest_timestamp (col1, col3) VALUES
    (9, date_trunc('month', LOCALTIMESTAMP - '3 months'::interval))
    , (10, date_trunc('month', LOCALTIMESTAMP - '3 months'::interval) + '14 days'::interval)
    , (11, date_trunc('month', LOCALTIMESTAMP - '2 months'::interval) - '1 second'::interval)
    , (12, date_trunc('month', LOCALTIMESTAMP - '2 months'::interval));

SELECT results_eq('SELECT partition_data_time(''partman_test.time_taptest_timestamp''::text, p_batch_count := 2)::int', ARRAY[4], 'Check that partition_data_time moves all four timestamp rows out of the default');
SELECT is_empty('SELECT * FROM ONLY partman_test.time_taptest_timestamp_default', 'Check that the timestamp default is empty');
SELECT results_eq('SELECT col1 FROM partman_test.time_taptest_timestamp_p'||to_char(date_trunc('month', CURRENT_DATE - '3 months'::interval), 'YYYYMMDD')||' ORDER BY col1',
    ARRAY[9, 10, 11], 'Check that time_taptest_timestamp_p'||to_char(date_trunc('month', CURRENT_DATE - '3 months'::interval), 'YYYYMMDD')||' holds its first and last second');
SELECT results_eq('SELECT col1 FROM partman_test.time_taptest_timestamp_p'||to_char(date_trunc('month', CURRENT_DATE - '2 months'::interval), 'YYYYMMDD')||' ORDER BY col1',
    ARRAY[12], 'Check that time_taptest_timestamp_p'||to_char(date_trunc('month', CURRENT_DATE - '2 months'::interval), 'YYYYMMDD')||' holds its first second');

SELECT * FROM finish();
ROLLBACK;
