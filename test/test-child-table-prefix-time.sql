-- ########## CUSTOM CHILD TABLE PREFIX TESTS (TIME) ##########
-- Covers part_config.child_table_prefix and its plumbing through
-- create_partition_time(), show_partition_name(), partition_data_time(),
-- and the not-empty check constraint.

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(7);
CREATE SCHEMA partman_test;

CREATE TABLE partman_test.time_prefix_table (
    col1 int
    , col2 timestamptz NOT NULL DEFAULT now())
    PARTITION BY RANGE (col2);

SELECT create_partition('partman_test.time_prefix_table', 'col2', '1 day', p_premake := 1, p_start_partition := CURRENT_DATE::text);

-- Default behavior (child_table_prefix defaults to '_p') is unaffected by this feature
SELECT has_table('partman_test', 'time_prefix_table_p'||to_char(CURRENT_DATE, 'YYYYMMDD'),
    'Default prefix (_p) still used for initial partition creation');

UPDATE part_config SET child_table_prefix = '_' WHERE parent_table = 'partman_test.time_prefix_table';

-- create_partition_time() should now use the custom prefix
SELECT create_partition_time('partman_test.time_prefix_table', ARRAY[(CURRENT_DATE + '5 days'::interval)]::timestamptz[]);
SELECT has_table('partman_test', 'time_prefix_table_'||to_char(CURRENT_DATE + '5 days'::interval, 'YYYYMMDD'),
    'create_partition_time() uses custom child_table_prefix');
SELECT hasnt_table('partman_test', 'time_prefix_table_p'||to_char(CURRENT_DATE + '5 days'::interval, 'YYYYMMDD'),
    'create_partition_time() does not fall back to the default _p prefix once customized');

-- show_partition_name() should reflect the custom prefix
SELECT results_eq(
    E'SELECT (show_partition_name(''partman_test.time_prefix_table'', (CURRENT_DATE + ''5 days''::interval)::text)).partition_table',
    ARRAY['time_prefix_table_'||to_char(CURRENT_DATE + '5 days'::interval, 'YYYYMMDD')],
    'show_partition_name() reflects custom child_table_prefix'
);

-- partition_data_time() should also honor the custom prefix when moving default data into a new child
INSERT INTO partman_test.time_prefix_table (col1, col2) VALUES (1, CURRENT_DATE + '6 days'::interval);
SELECT is_empty('SELECT * FROM ONLY partman_test.time_prefix_table', 'Data outside any existing child goes to the default partition');
SELECT partition_data_time('partman_test.time_prefix_table');
SELECT has_table('partman_test', 'time_prefix_table_'||to_char(CURRENT_DATE + '6 days'::interval, 'YYYYMMDD'),
    'partition_data_time() uses custom child_table_prefix when creating the child table');

-- ##### CONSTRAINT #####

SELECT throws_ok(
    $$UPDATE part_config SET child_table_prefix = '' WHERE parent_table = 'partman_test.time_prefix_table'$$,
    '23514',
    NULL,
    'Empty child_table_prefix is rejected by check constraint'
);

SELECT * FROM finish();
ROLLBACK;
