-- ########## TIME MONTHLY DATE BOUNDARY ##########
-- Other tests:
    -- partition_data_time() with a date and a timestamp without time zone control column
    -- Rows on the first day of a month must go to that month's child table (See Github Issues #838 and #868)
    -- Uses a non-UTC time zone so timestamptz text output has a non-zero offset

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);
SET LOCAL timezone = 'America/New_York';

SELECT plan(14);
CREATE SCHEMA partman_test;

CREATE TABLE partman_test.date_taptest_table
    (col1 int NOT NULL
     , col2 date NOT NULL)
    PARTITION BY RANGE (col2);

CREATE TABLE partman_test.ts_taptest_table
    (col1 int NOT NULL
     , col2 timestamp NOT NULL)
    PARTITION BY RANGE (col2);

SELECT create_parent('partman_test.date_taptest_table', 'col2', '1 month');
SELECT create_parent('partman_test.ts_taptest_table', 'col2', '1 month');

-- Old values far from now, so they all go to the default table first
INSERT INTO partman_test.date_taptest_table (col1, col2) VALUES
    (1, '2002-06-15'), (2, '2002-07-01'), (3, '2002-07-15'), (4, '2002-08-01');
INSERT INTO partman_test.ts_taptest_table (col1, col2) VALUES
    (1, '2002-06-15 12:00:00'), (2, '2002-07-01 00:00:00'), (3, '2002-07-15 12:00:00'), (4, '2002-08-01 00:00:00');

SELECT results_eq('SELECT partition_data_time(''partman_test.date_taptest_table'', p_batch_count := 10)::int', ARRAY[4], 'Check that partition_data_time moved all 4 rows of date_taptest_table');

SELECT has_table('partman_test', 'date_taptest_table_p20020601', 'Check date_taptest_table_p20020601 exists');
SELECT has_table('partman_test', 'date_taptest_table_p20020701', 'Check date_taptest_table_p20020701 exists');
SELECT has_table('partman_test', 'date_taptest_table_p20020801', 'Check date_taptest_table_p20020801 exists');
SELECT results_eq('SELECT col1 FROM partman_test.date_taptest_table_p20020601 ORDER BY col1', ARRAY[1], 'Check rows in date_taptest_table_p20020601');
SELECT results_eq('SELECT col1 FROM partman_test.date_taptest_table_p20020701 ORDER BY col1', ARRAY[2,3], 'Check rows in date_taptest_table_p20020701');
SELECT results_eq('SELECT col1 FROM partman_test.date_taptest_table_p20020801 ORDER BY col1', ARRAY[4], 'Check rows in date_taptest_table_p20020801');
SELECT is_empty('SELECT * FROM partman_test.date_taptest_table_default', 'Check that date_taptest_table_default is empty');

SELECT results_eq('SELECT partition_data_time(''partman_test.ts_taptest_table'', p_batch_count := 10)::int', ARRAY[4], 'Check that partition_data_time moved all 4 rows of ts_taptest_table');

SELECT has_table('partman_test', 'ts_taptest_table_p20020701', 'Check ts_taptest_table_p20020701 exists');
SELECT results_eq('SELECT col1 FROM partman_test.ts_taptest_table_p20020601 ORDER BY col1', ARRAY[1], 'Check rows in ts_taptest_table_p20020601');
SELECT results_eq('SELECT col1 FROM partman_test.ts_taptest_table_p20020701 ORDER BY col1', ARRAY[2,3], 'Check rows in ts_taptest_table_p20020701');
SELECT results_eq('SELECT col1 FROM partman_test.ts_taptest_table_p20020801 ORDER BY col1', ARRAY[4], 'Check rows in ts_taptest_table_p20020801');
SELECT is_empty('SELECT * FROM partman_test.ts_taptest_table_default', 'Check that ts_taptest_table_default is empty');

SELECT * FROM finish();
ROLLBACK;
