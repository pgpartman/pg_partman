-- ########## TIME DAILY TESTS ##########
-- Other tests:
    -- Test that replica identity is inherited

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(26);

CREATE SCHEMA partman_test;

CREATE TABLE partman_test.time_taptest_table
    (col1 int
        , col2 text default 'stuff'
        , col3 timestamptz NOT NULL DEFAULT now())
    PARTITION BY RANGE (col3);

ALTER TABLE partman_test.time_taptest_table REPLICA IDENTITY FULL;

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

SELECT * FROM finish();
ROLLBACK;
