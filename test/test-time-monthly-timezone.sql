-- ########## TIME MONTHLY TIMEZONE ##########
-- Regression test for boundary drift when run_maintenance() is invoked from a
-- session timezone different from the one the partition set was created in.
--
-- A monthly set is created while the session is in Europe/Moscow (UTC+3), so
-- every boundary is Moscow local midnight. Maintenance is then run from a UTC
-- session (as many client drivers, e.g. DataGrip, do by default). The new
-- child tables must stay aligned to the set's creation timezone; before the
-- fix their boundaries drifted (e.g. a "December" partition covering Dec 01 ->
-- Dec 31 and named p<...>1130) because timestamptz month arithmetic was done
-- in the session timezone.

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(7);
CREATE SCHEMA partman_test;

SET timezone = 'Europe/Moscow';

CREATE TABLE partman_test.time_taptest_table
    (col1 bigserial
     , col3 timestamptz DEFAULT now() NOT NULL)
    PARTITION BY RANGE (col3);

SELECT create_parent('partman_test.time_taptest_table', 'col3', '1 month', p_premake := 4);

-- A row in the current month so run_maintenance() premakes ahead of "now".
INSERT INTO partman_test.time_taptest_table (col3) VALUES (CURRENT_TIMESTAMP);

-- The creating session's timezone is recorded so future maintenance stays aligned.
SELECT results_eq(
    $$SELECT partition_timezone FROM part_config WHERE parent_table = 'partman_test.time_taptest_table'$$,
    ARRAY['Europe/Moscow'],
    'Creation timezone recorded in part_config');

-- Sanity: the last partition created up front is aligned to Moscow midnight.
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('month', CURRENT_TIMESTAMP)+'4 months'::interval, 'YYYYMMDD'),
    'Pre-maintenance: month +4 partition exists');

-- Now a client with UTC (server or driver default) runs maintenance.
UPDATE part_config SET premake = 6 WHERE parent_table = 'partman_test.time_taptest_table';
SET timezone = 'UTC';
SELECT run_maintenance('partman_test.time_taptest_table');
-- Evaluate expectations back in the creation timezone.
SET timezone = 'Europe/Moscow';

-- The newly created partitions must keep the Moscow-midnight alignment.
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('month', CURRENT_TIMESTAMP)+'5 months'::interval, 'YYYYMMDD'),
    'Month +5 partition created under UTC session stays aligned to creation tz');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('month', CURRENT_TIMESTAMP)+'6 months'::interval, 'YYYYMMDD'),
    'Month +6 partition created under UTC session stays aligned to creation tz');

-- Strong check on the actual boundaries, not just the names.
SELECT results_eq(
    format($$SELECT child_start_time FROM show_partition_info(%L, '1 month', 'partman_test.time_taptest_table')$$,
        'partman_test.time_taptest_table_p'||to_char(date_trunc('month', CURRENT_TIMESTAMP)+'5 months'::interval, 'YYYYMMDD')),
    ARRAY[date_trunc('month', CURRENT_TIMESTAMP)+'5 months'::interval]::timestamptz[],
    'Month +5 start boundary is Moscow midnight, not shifted');
SELECT results_eq(
    format($$SELECT child_start_time FROM show_partition_info(%L, '1 month', 'partman_test.time_taptest_table')$$,
        'partman_test.time_taptest_table_p'||to_char(date_trunc('month', CURRENT_TIMESTAMP)+'6 months'::interval, 'YYYYMMDD')),
    ARRAY[date_trunc('month', CURRENT_TIMESTAMP)+'6 months'::interval]::timestamptz[],
    'Month +6 start boundary is Moscow midnight, not shifted');

-- premake is 6, so no seventh future partition should have been made.
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('month', CURRENT_TIMESTAMP)+'7 months'::interval, 'YYYYMMDD'),
    'Month +7 partition not created (premake honored)');

SELECT * FROM finish();
ROLLBACK;
