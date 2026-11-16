-- ########## CUSTOM CHILD TABLE PREFIX TESTS (ID) ##########
-- Covers part_config.child_table_prefix and its plumbing through
-- create_partition_id(), show_partition_name(), and partition_data_id().

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(5);
CREATE SCHEMA partman_test;

CREATE TABLE partman_test.id_prefix_table (col1 bigint PRIMARY KEY) PARTITION BY RANGE (col1);

SELECT create_partition('partman_test.id_prefix_table', 'col1', '10', p_start_partition := '100', p_premake := 1);

-- Default behavior (child_table_prefix defaults to '_p') is unaffected by this feature
SELECT has_table('partman_test', 'id_prefix_table_p100', 'Default prefix (_p) still used for initial partition creation');

UPDATE part_config SET child_table_prefix = '_batch_' WHERE parent_table = 'partman_test.id_prefix_table';

-- create_partition_id() should now use the custom prefix
SELECT create_partition_id('partman_test.id_prefix_table', ARRAY[200]::bigint[]);
SELECT has_table('partman_test', 'id_prefix_table_batch_200', 'create_partition_id() uses custom child_table_prefix');
SELECT hasnt_table('partman_test', 'id_prefix_table_p200', 'create_partition_id() does not fall back to the default _p prefix once customized');

-- show_partition_name() should reflect the custom prefix
SELECT results_eq(
    E'SELECT (show_partition_name(''partman_test.id_prefix_table'', ''205'')).partition_table',
    ARRAY['id_prefix_table_batch_200'],
    'show_partition_name() reflects custom child_table_prefix for id partitioning'
);

-- partition_data_id() should also honor the custom prefix when moving default data into a new child
INSERT INTO partman_test.id_prefix_table (col1) VALUES (300);
SELECT partition_data_id('partman_test.id_prefix_table');
SELECT has_table('partman_test', 'id_prefix_table_batch_300', 'partition_data_id() uses custom child_table_prefix when creating the child table');

SELECT * FROM finish();
ROLLBACK;
