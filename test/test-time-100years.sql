-- ########## TIME CUSTOM TESTS NATIVE ##########
-- Other tests: 
    -- 100 year interval
    -- inherit privileges
    -- privilege inheritance
    -- no default

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(147);
CREATE SCHEMA partman_test;
CREATE SCHEMA partman_retention_test;
CREATE ROLE partman_basic;
CREATE ROLE partman_revoke;
CREATE ROLE partman_owner;

CREATE TABLE partman_test.time_taptest_table 
    (col1 int
     , col2 text
     , col3 timestamptz NOT NULL DEFAULT now()) 
    PARTITION BY RANGE (col3);
CREATE TABLE partman_test.time_taptest_table_template (LIKE partman_test.time_taptest_table INCLUDING ALL);
ALTER TABLE partman_test.time_taptest_table_template ADD PRIMARY KEY (col1);
CREATE TABLE partman_test.undo_taptest (LIKE partman_test.time_taptest_table INCLUDING ALL);

CREATE INDEX ON partman_test.time_taptest_table (col3);

GRANT SELECT,INSERT,UPDATE ON partman_test.time_taptest_table TO partman_basic;
GRANT ALL ON partman_test.time_taptest_table TO partman_revoke;

SELECT create_parent('partman_test.time_taptest_table', 'col3', '100 years', p_template_table => 'partman_test.time_taptest_table_template', p_default_table => false);
UPDATE part_config SET inherit_privileges = TRUE;
SELECT reapply_privileges('partman_test.time_taptest_table');

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(1,10), CURRENT_TIMESTAMP);

SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'), 'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'500 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'500 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_default', 'Check time_taptest_table_default does not exist');

SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'));

SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'));

SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'));

SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'), 
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'));

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON partman_test.time_taptest_table FROM partman_revoke;
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(11,20), CURRENT_TIMESTAMP + '100 years'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(21,25), CURRENT_TIMESTAMP + '200 years'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(26,30), CURRENT_TIMESTAMP + '300 years'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(31,37), CURRENT_TIMESTAMP + '400 years'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(40,49), CURRENT_TIMESTAMP - '100 years'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(50,70), CURRENT_TIMESTAMP - '200 years'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(71,85), CURRENT_TIMESTAMP - '300 years'::interval);
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(86,100), CURRENT_TIMESTAMP - '400 years'::interval);

SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'), 
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'), 
    ARRAY[5], 'Check count from time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'), 
    ARRAY[5], 'Check count from time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'), 
    ARRAY[7], 'Check count from time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'), 
    ARRAY[10], 'Check count from time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'), 
    ARRAY[21], 'Check count from time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'), 
    ARRAY[15], 'Check count from time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'), 
    ARRAY[15], 'Check count from time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'));

UPDATE part_config SET premake = 5 WHERE parent_table = 'partman_test.time_taptest_table';
SELECT run_maintenance();

INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(101,122), CURRENT_TIMESTAMP + '500 years'::interval);

SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'));

SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'), 
    ARRAY[22], 'Check count from time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'));

SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'), 'partman_basic', 
ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'), 'partman_basic', 
ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'), 'partman_basic', 
ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'), 'partman_basic', 
ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'), 'partman_basic', 
ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'));

SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT'], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT'], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT'], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT'], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    ARRAY['SELECT'], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'));

GRANT DELETE ON partman_test.time_taptest_table TO partman_basic;
REVOKE ALL ON partman_test.time_taptest_table FROM partman_revoke;
ALTER TABLE partman_test.time_taptest_table OWNER TO partman_owner;

UPDATE part_config SET premake = 6 WHERE parent_table = 'partman_test.time_taptest_table';
SELECT run_maintenance();
INSERT INTO partman_test.time_taptest_table (col1, col3) VALUES (generate_series(123,150), CURRENT_TIMESTAMP + '600 years'::interval);

SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table', ARRAY[148], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'), 
    ARRAY[28], 'Check count from time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'));

SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1200 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1200 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'));
SELECT col_is_pk('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'));

SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE','DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE','DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'));

SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'));

SELECT reapply_privileges('partman_test.time_taptest_table');
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'));

SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'));
SELECT table_privs_are('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'));

SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'));

SELECT drop_partition_time('partman_test.time_taptest_table', '300 years', p_keep_table := false);
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'400 years'::interval, 'YYYYMMDD')||' does not exist');

UPDATE part_config SET retention = '200 years'::interval WHERE parent_table = 'partman_test.time_taptest_table';
SELECT drop_partition_time('partman_test.time_taptest_table', p_retention_schema := 'partman_retention_test');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT has_table('partman_retention_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'300 years'::interval, 'YYYYMMDD')||' got moved to new schema');

SELECT undo_partition('partman_test.time_taptest_table', p_loop_count => 20, p_target_table := 'partman_test.undo_taptest', p_keep_table := false);
SELECT results_eq('SELECT count(*)::int FROM partman_test.undo_taptest', ARRAY[118], 'Check count from target table after undo');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP), 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'100 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)-'200 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'100 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'200 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'300 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'400 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'500 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'600 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'700 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'800 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'900 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1000 years'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('partman_test', 'time_taptest_table_p'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD'), 
    'Check time_taptest_table_'||to_char(date_trunc('century', CURRENT_TIMESTAMP)+'1100 years'::interval, 'YYYYMMDD')||' does not exist');


SELECT hasnt_table('partman_test', 'time_taptest_table_template', 'Check that template table was dropped');

SELECT * FROM finish();
ROLLBACK;
