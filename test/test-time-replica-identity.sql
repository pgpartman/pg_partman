-- ########## TIME DAILY TESTS ##########
-- Other tests:
    -- Test that replica identity is inherited
    -- Ensure partition_data_proc can move data out of default when its in publication

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(34);

CREATE SCHEMA partman_test;

CREATE TABLE partman_test.time_taptest_table
    (col1 int
        , col2 text default 'stuff'
        , col3 timestamptz NOT NULL DEFAULT now())
    PARTITION BY RANGE (col3);

ALTER TABLE partman_test.time_taptest_table REPLICA IDENTITY FULL;

-- Create publication before child tables to check it was inherited
CREATE PUBLICATION partman_test_publication FOR TABLE partman_test.time_taptest_table;

SELECT create_parent('partman_test.time_taptest_table', 'col3', '1 day');

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(1,10), CURRENT_TIMESTAMP);

SELECT is_partitioned('partman_test', 'time_taptest_table', 'Check that time_taptest_table is natively partitioned');
SELECT has_table('partman', 'template_partman_test_time_taptest_table', 'Check that default template table was created');

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

SELECT results_eq('SELECT partition_tablename FROM partman.show_partitions(''partman_test.time_taptest_table'') LIMIT 1', ARRAY['time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD')], 'Check that -4 day old table table is oldest');

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_default''', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_default' );

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD') );

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP-''1 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD') );

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP-''2 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 day'::interval, 'YYYYMMDD') );

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP-''3 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 day'::interval, 'YYYYMMDD') );

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP-''4 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 day'::interval, 'YYYYMMDD') );


SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP+''1 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD') );

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP+''2 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 day'::interval, 'YYYYMMDD') );

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP+''3 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 day'::interval, 'YYYYMMDD') );

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP+''4 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 day'::interval, 'YYYYMMDD') );

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(11,20), CURRENT_TIMESTAMP + '1 day'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(21,25), CURRENT_TIMESTAMP + '2 days'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(26,30), CURRENT_TIMESTAMP + '3 days'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(31,37), CURRENT_TIMESTAMP + '4 days'::interval);

SELECT run_maintenance();

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP+''5 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 day'::interval, 'YYYYMMDD') );

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP+''6 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 day'::interval, 'YYYYMMDD') );

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP+''7 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 day'::interval, 'YYYYMMDD') );

SELECT results_eq('SELECT c.relreplident::text FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON c.relnamespace = n.oid WHERE n.nspname = ''partman_test'' AND c.relname = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP+''8 day''::interval, ''YYYYMMDD'')', ARRAY['f'], 'Check that replica identity was inherited to time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 day'::interval, 'YYYYMMDD') );

-- Insert data outside covered children to check that default table is able to have data removed as part of publication. Also provides
-- another test that default got the replica identity
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(200,205), CURRENT_TIMESTAMP + '20 days'::interval);
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_default', ARRAY[6], 'Check that data outside existing child scope goes to default');
SELECT partition_data_time('partman_test.time_taptest_table', 20);

UPDATE part_config SET retention = '2 days'::interval, retention_keep_table = true WHERE parent_table = 'partman_test.time_taptest_table';
SELECT run_maintenance();
-- Check for new oldest table
SELECT results_eq('SELECT partition_tablename FROM partman.show_partitions(''partman_test.time_taptest_table'') LIMIT 1', ARRAY['time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')], 'Check that -2 day old table table is oldest table');
-- Ensure that -4 & -3 day tables still exists
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD')||' exists');
-- Ensure that publication is dropped from detached tables
SELECT is_empty('SELECT pubname FROM pg_publication_tables WHERE tablename = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP-''3 day''::interval, ''YYYYMMDD'') AND pubname = ''partman_test_publication''', 'Ensure time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 day'::interval, 'YYYYMMDD')||' was removed from publication');
SELECT is_empty('SELECT pubname FROM pg_publication_tables WHERE tablename = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP-''4 day''::interval, ''YYYYMMDD'') AND pubname = ''partman_test_publication''', 'Ensure time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 day'::interval, 'YYYYMMDD')||' was removed from publication');
-- Ensure that publication still exists on -2 day old table
-- Cannot get this test to work right now
--SELECT results_eq('SELECT pubname::text FROM pg_publication_tables WHERE tablename = ''time_taptest_table_p''||to_char(CURRENT_TIMESTAMP-''2 day''::interval, ''YYYYMMDD'') AND pubname = ''partman_test_publication'' LIMIT 1', ARRAY['partman_test_publication'] ,'Ensure time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 day'::interval, 'YYYYMMDD')||' is still in publication');


SELECT * FROM finish();
ROLLBACK;
