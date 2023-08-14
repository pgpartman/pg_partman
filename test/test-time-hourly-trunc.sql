-- ########## TIME TESTS ##########
-- Other tests: Long name truncation

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(121);
CREATE SCHEMA partman_test;
CREATE ROLE partman_basic;
CREATE ROLE partman_revoke;
CREATE ROLE partman_owner;

CREATE TABLE partman_test.time_taptest_table_1234567890123456789012345678901234567890 (
    col1 int
    , col2 text
    , col3 timestamptz NOT NULL DEFAULT now())
    PARTITION BY RANGE (col3);
CREATE TABLE partman_test.template_time_taptest_table (LIKE partman_test.time_taptest_table_1234567890123456789012345678901234567890);
ALTER TABLE partman_test.template_time_taptest_table ADD PRIMARY KEY (col1);
CREATE TABLE partman_test.undo_taptest (LIKE partman_test.time_taptest_table_1234567890123456789012345678901234567890 INCLUDING ALL);

GRANT SELECT,INSERT,UPDATE ON partman_test.time_taptest_table_1234567890123456789012345678901234567890 TO partman_basic;
GRANT ALL ON partman_test.time_taptest_table_1234567890123456789012345678901234567890 TO partman_revoke;

SELECT create_parent('partman_test.time_taptest_table_1234567890123456789012345678901234567890'
    , 'col3'
    , '1 hour'
    , p_template_table => 'partman_test.template_time_taptest_table');

UPDATE part_config SET inherit_privileges = true;
SELECT reapply_privileges('partman_test.time_taptest_table_1234567890123456789012345678901234567890');

INSERT INTO partman_test.time_taptest_table_1234567890123456789012345678901234567890 (col1, col3) VALUES (generate_series(1,10), CURRENT_TIMESTAMP);

SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), 'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'));

SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567890123456_default', 'Check that default table has had data moved to partition');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_1234567890123456789012345678901234567890', ARRAY[10], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), 
    ARRAY[10], 'Check count from time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'));

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON partman_test.time_taptest_table_1234567890123456789012345678901234567890 FROM partman_revoke;
INSERT INTO partman_test.time_taptest_table_1234567890123456789012345678901234567890 (col1, col3) VALUES (generate_series(11,20), CURRENT_TIMESTAMP + '1 hour'::interval);
INSERT INTO partman_test.time_taptest_table_1234567890123456789012345678901234567890 (col1, col3) VALUES (generate_series(21,25), CURRENT_TIMESTAMP + '2 hours'::interval);

SELECT is_empty('SELECT * FROM ONLY partman_test.time_taptest_table_1234567890123456789012345678901234567890', 'Check that parent table has had no data inserted to it');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_1234567890123456789012345678901234567890', ARRAY[25], 'Check count from time_taptest_table');
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    ARRAY[10], 'Check count from time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    ARRAY[5], 'Check count from time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'));

UPDATE part_config SET premake = 5 WHERE parent_table = 'partman_test.time_taptest_table_1234567890123456789012345678901234567890';
SELECT run_maintenance();
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    ARRAY['SELECT'], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    ARRAY['SELECT'], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    ARRAY['SELECT'], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'));

GRANT DELETE ON partman_test.time_taptest_table_1234567890123456789012345678901234567890 TO partman_basic;
REVOKE ALL ON partman_test.time_taptest_table_1234567890123456789012345678901234567890 FROM partman_revoke;
ALTER TABLE partman_test.time_taptest_table_1234567890123456789012345678901234567890 OWNER TO partman_owner;

UPDATE part_config SET premake = 6 WHERE parent_table = 'partman_test.time_taptest_table_1234567890123456789012345678901234567890';
SELECT run_maintenance();
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT hasnt_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'9 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'9 hours'::interval, 'YYYYMMDD_HH24MISS')||' exists');
SELECT col_is_pk('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), ARRAY['col1'], 
    'Check for primary key in time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), 'partman_basic', ARRAY['SELECT','INSERT','UPDATE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'));

INSERT INTO partman_test.time_taptest_table_1234567890123456789012345678901234567890 (col1, col3) VALUES (generate_series(200,210), CURRENT_TIMESTAMP + '20 hours'::interval);
SELECT results_eq('SELECT count(*)::int FROM partman_test.time_taptest_table_123456789012345678901234567890123456_default', ARRAY[11], 'Check that data outside scope goes to default');

SELECT reapply_privileges('partman_test.time_taptest_table_1234567890123456789012345678901234567890');
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check partman_basic privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'));

SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_privs_are('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_revoke', 
    '{}'::text[], 'Check partman_revoke privileges of time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'));

SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP), 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'));
SELECT table_owner_is ('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 'partman_owner', 
    'Check that ownership change worked for time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'));

SELECT undo_partition('partman_test.time_taptest_table_1234567890123456789012345678901234567890', p_loop_count => 20, p_target_table := 'partman_test.undo_taptest');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)-'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'1 hour'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'2 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'3 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'4 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'5 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'6 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'7 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');
SELECT has_table('partman_test', 'time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' still exists');
SELECT is_empty('SELECT * FROM partman_test.time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS'), 
    'Check time_taptest_table_123456789012345678901234567_p'||to_char(date_trunc('hour', CURRENT_TIMESTAMP)+'8 hours'::interval, 'YYYYMMDD_HH24MISS')||' is empty');

SELECT * FROM finish();
ROLLBACK;
