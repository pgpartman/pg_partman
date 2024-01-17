-- ########## TIME TESTS WITH BACKGROUND WORKER RUNNING ##########
-- Other tests: create_parent() returns true
    -- retention to new schema
    -- retention keep indexes
    -- privileges inherited to children
-- Set the pg_partman_bgw.interval setting in postgresql.conf to 10 seconds (or less) in order for this test suite to pass successfully.

-- ########### WARNING WARNING WARNING ##############
-- Cannot run this test inside a transaction since then the BGW would not see this partition set exists
-- ########### WARNING WARNING WARNING ##############


\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

--BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(105);
CREATE SCHEMA partman_test;
CREATE SCHEMA partman_retention_test;
CREATE ROLE partman_basic;
CREATE ROLE partman_revoke;
CREATE ROLE partman_owner;

CREATE TABLE partman_test.time_taptest_table (
    col1 int
    , col2 text
    , col3 timestamptz NOT NULL DEFAULT now() )
    PARTITION BY RANGE (col3);
GRANT SELECT,INSERT,UPDATE ON partman_test.time_taptest_table TO partman_basic;
GRANT ALL ON partman_test.time_taptest_table TO partman_revoke;

CREATE TABLE partman_test.template_time_taptest_table (LIKE partman_test.time_taptest_table);
ALTER TABLE partman_test.template_time_taptest_table ADD PRIMARY KEY (col1);

CREATE TABLE partman_test.undo_taptest (LIKE partman_test.time_taptest_table INCLUDING ALL);

SELECT create_parent('partman_test.time_taptest_table', 'col3', '1 day', p_template_table := 'partman_test.template_time_taptest_table' );

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(1,10), CURRENT_TIMESTAMP);

UPDATE part_config SET inherit_privileges = true WHERE parent_table = 'partman_test.time_taptest_table';
SELECT reapply_privileges('partman_test.time_taptest_table');

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
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' exists');
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'partman_revoke',
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'partman_revoke',
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'],
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));

SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table', ARRAY[10], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'),
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON partman_test.time_taptest_table FROM partman_revoke;
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(11,20), CURRENT_TIMESTAMP + '1 day'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(21,25), CURRENT_TIMESTAMP + '2 days'::interval);

SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table', ARRAY[25], 'Check count from time_taptest_table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'),
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'),
    ARRAY[5], 'Check count from time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));

UPDATE part_config SET premake = 5 WHERE parent_table = 'partman_test.time_taptest_table';
SELECT pass('Waiting 20 seconds for background worker to run...');
SELECT pg_sleep(20);

SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD')||' exists');
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));

SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 'partman_basic',
ARRAY['SELECT','INSERT','UPDATE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 'partman_basic',
ARRAY['SELECT','INSERT','UPDATE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 'partman_basic',
ARRAY['SELECT','INSERT','UPDATE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    ARRAY['SELECT'], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    ARRAY['SELECT'], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    ARRAY['SELECT'], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));

GRANT DELETE ON partman_test.time_taptest_table TO partman_basic;
REVOKE ALL ON partman_test.time_taptest_table FROM partman_revoke;
ALTER TABLE partman_test.time_taptest_table OWNER TO partman_owner;

UPDATE part_config SET premake = 6 WHERE parent_table = 'partman_test.time_taptest_table';
SELECT pass('Waiting 20 seconds for background worker to run...');
SELECT pg_sleep(20);

SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD')||' exists');
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), ARRAY['col1'],
    'Check for primary key in time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));

SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 'partman_owner',
    'Check that ownership change worked for time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(200,210), CURRENT_TIMESTAMP + '20 days'::interval);
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_default', ARRAY[11], 'Check that data outside scope goes to default');

SELECT reapply_privileges('partman_test.time_taptest_table');
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 'partman_basic',
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'],
    'Check partman_basic privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));

SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'partman_revoke',
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'partman_revoke',
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 'partman_revoke',
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));

SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'partman_owner',
    'Check that ownership change worked for time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'partman_owner',
    'Check that ownership change worked for time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'partman_owner',
    'Check that ownership change worked for time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'partman_owner',
    'Check that ownership change worked for time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'partman_owner',
    'Check that ownership change worked for time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 'partman_owner',
    'Check that ownership change worked for time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 'partman_owner',
    'Check that ownership change worked for time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 'partman_owner',
    'Check that ownership change worked for time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 'partman_owner',
    'Check that ownership change worked for time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));

SELECT drop_partition_time('partman_test.time_taptest_table', '3 days', p_keep_table := false);
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD')||' does not exist');

UPDATE part_config SET retention = '2 days'::interval, retention_schema = 'partman_retention_test' WHERE parent_table = 'partman_test.time_taptest_table';
SELECT pass('Waiting 20 seconds for background worker to run...');
SELECT pg_sleep(20);

SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT has_table('partman_retention_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD')||' got moved to new schema');

SELECT undo_partition('partman_test.time_taptest_table', 'partman_test.undo_taptest', 20);
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD')||' is empty');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')||' is empty');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'),
    'Check time_taptest_table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD')||' is empty');

DROP SCHEMA IF EXISTS partman_test CASCADE;
DROP SCHEMA IF EXISTS partman_retention_test CASCADE;
DROP ROLE IF EXISTS partman_basic;
DROP ROLE IF EXISTS partman_revoke;
DROP ROLE IF EXISTS partman_owner;

SELECT hasnt_schema('partman_test', 'Ensure partman_test schema has been dropped');
SELECT hasnt_schema('partman_retention_test', 'Ensure partman_retention_test schema has been dropped');
SELECT hasnt_role('partman_basic', 'Ensure partman_basic role has been dropped');
SELECT hasnt_role('partman_revoke', 'Ensure partman_revoke role has been dropped');
SELECT hasnt_role('partman_owner', 'Ensure partman_owner role has been dropped');

SELECT * FROM finish();
--ROLLBACK;
