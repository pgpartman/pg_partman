-- ########## TIME DAILY TESTS ##########
-- Other tests: check that maintenance catches up if tables are missing
    -- Test using default template table. Initial child tables will have no indexes. New tables after template has indexes added should.
    -- Mixed case

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(222);

CREATE SCHEMA "Partman_Test";
CREATE SCHEMA "Partman_Retention_Test";
CREATE ROLE "Partman_Basic";
CREATE ROLE "Partman_Revoke";
CREATE ROLE "Partman_Owner";

CREATE TABLE "Partman_Test"."FK_Test_Reference" ("Col2" text unique not null);
INSERT INTO "Partman_Test"."FK_Test_Reference" VALUES ('stuff');

CREATE TABLE "Partman_Test"."Time_Taptest_Table" ("Col1" int, "Col2" text default 'stuff', "Col3" timestamptz NOT NULL DEFAULT now()) PARTITION BY RANGE ("Col3");
CREATE TABLE "Partman_Test"."Undo_Taptest" (LIKE "Partman_Test"."Time_Taptest_Table" INCLUDING ALL);
GRANT SELECT,INSERT,UPDATE ON "Partman_Test"."Time_Taptest_Table" TO "Partman_Basic";
GRANT ALL ON "Partman_Test"."Time_Taptest_Table" TO "Partman_Revoke";
ALTER TABLE "Partman_Test"."Time_Taptest_Table" OWNER TO "Partman_Owner";

SELECT create_parent('Partman_Test.Time_Taptest_Table', 'Col3', '1 day');
UPDATE part_config SET inherit_privileges = TRUE;
SELECT reapply_privileges('Partman_Test.Time_Taptest_Table');


SELECT is_partitioned('Partman_Test', 'Time_Taptest_Table', 'Check that Time_Taptest_Table is natively partitioned');
SELECT has_table('partman', 'template_Partman_Test_Time_Taptest_Table', 'Check that default template table was created');
SELECT table_owner_is ('partman', 'template_Partman_Test_Time_Taptest_Table', 'Partman_Owner', 
    'Check that template table ownership is set properly');

-- Add inheritable stuff to template table
ALTER TABLE "template_Partman_Test_Time_Taptest_Table" ADD PRIMARY KEY ("Col1");
ALTER TABLE "template_Partman_Test_Time_Taptest_Table" ADD FOREIGN KEY ("Col2") REFERENCES "Partman_Test"."FK_Test_Reference"("Col2");

INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(1,10), CURRENT_TIMESTAMP);

SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'5 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'5 days'::interval, 'YYYYMMDD')||' does not exist');

SELECT col_isnt_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for NO primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT col_isnt_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for NO primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for NO primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for NO primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for NO primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for NO primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT col_isnt_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for NO primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for NO primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for NO primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'));
SELECT col_isnt_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for NO primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'));

SELECT col_isnt_fk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), ARRAY['Col2'], 
    'Check for NO foreign key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT col_isnt_fk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), ARRAY['Col2'], 
    'Check for NO foreign key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT col_isnt_fk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 day'::interval, 'YYYYMMDD'), ARRAY['Col2'], 
    'Check for NO foreign key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 day'::interval, 'YYYYMMDD'));
SELECT col_isnt_fk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 day'::interval, 'YYYYMMDD'), ARRAY['Col2'], 
    'Check for NO foreign key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 day'::interval, 'YYYYMMDD'));
SELECT col_isnt_fk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 day'::interval, 'YYYYMMDD'), ARRAY['Col2'], 
    'Check for NO foreign key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 day'::interval, 'YYYYMMDD'));
SELECT col_isnt_fk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), ARRAY['Col2'], 
    'Check for NO foreign key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT col_isnt_fk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 day'::interval, 'YYYYMMDD'), ARRAY['Col2'], 
    'Check for NO foreign key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 day'::interval, 'YYYYMMDD'));
SELECT col_isnt_fk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 day'::interval, 'YYYYMMDD'), ARRAY['Col2'], 
    'Check for NO foreign key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 day'::interval, 'YYYYMMDD'));
SELECT col_isnt_fk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 day'::interval, 'YYYYMMDD'), ARRAY['Col2'], 
    'Check for NO foreign key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 day'::interval, 'YYYYMMDD'));

SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'));

SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'], 
    'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'));

SELECT is_empty('SELECT * FROM "Partman_Test"."Time_Taptest_Table_default"', 'Check that default table is empty.');
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table"', ARRAY[10], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD')||'"', 
    ARRAY[10], 'Check count from Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON "Partman_Test"."Time_Taptest_Table" FROM "Partman_Revoke";
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(11,20), CURRENT_TIMESTAMP + '1 day'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(21,25), CURRENT_TIMESTAMP + '2 days'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(26,30), CURRENT_TIMESTAMP + '3 days'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(31,37), CURRENT_TIMESTAMP + '4 days'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(40,49), CURRENT_TIMESTAMP - '1 day'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(50,70), CURRENT_TIMESTAMP - '2 days'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(71,85), CURRENT_TIMESTAMP - '3 days'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(86,100), CURRENT_TIMESTAMP - '4 days'::interval);

SELECT is_empty('SELECT * FROM "Partman_Test"."Time_Taptest_Table_default"', 'Check that default table is empty.');
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD')||'"', 
    ARRAY[10], 'Check count from Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||'"', 
    ARRAY[5], 'Check count from Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||'"', 
    ARRAY[5], 'Check count from Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||'"', 
    ARRAY[7], 'Check count from Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD')||'"', 
    ARRAY[10], 'Check count from Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')||'"', 
    ARRAY[21], 'Check count from Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD')||'"', 
    ARRAY[15], 'Check count from Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'));
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD')||'"', 
    ARRAY[15], 'Check count from Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'));

UPDATE part_config SET premake = 5 WHERE parent_table = 'Partman_Test.Time_Taptest_Table';

-- Run to create proper future partitions
SELECT run_maintenance();
-- Insert after maintenance since native fails with no child
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(101,122), CURRENT_TIMESTAMP + '5 days'::interval);
-- Run again to create +5 partition now that data exists
SELECT run_maintenance();

-- Data exists for +5 days, with 5 premake so +10 day table should exist
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD')||' does not exist');

SELECT col_is_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'));


SELECT is_empty('SELECT * FROM "Partman_Test"."Time_Taptest_Table_default"', 'Check that default table is empty.');
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||'"', 
    ARRAY[22], 'Check count from Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));

SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'Partman_Basic', ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'));

SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT'], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));

GRANT DELETE ON "Partman_Test"."Time_Taptest_Table" TO "Partman_Basic";
REVOKE ALL ON "Partman_Test"."Time_Taptest_Table" FROM "Partman_Revoke";

ALTER TABLE "Partman_Test"."Time_Taptest_Table" OWNER TO "Partman_Owner";

UPDATE part_config SET premake = 6 WHERE parent_table = 'Partman_Test.Time_Taptest_Table';
SELECT run_maintenance();
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(123,150), CURRENT_TIMESTAMP + '6 days'::interval);
-- Run again now that +6 data exists
SELECT run_maintenance();

SELECT is_empty('SELECT * FROM "Partman_Test"."Time_Taptest_Table_default"', 'Check that default table is empty.');
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table"', ARRAY[148], 'Check count from parent table');
SELECT results_eq('SELECT count(*)::int FROM "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD')||'"', 
    ARRAY[28], 'Check count from Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));

SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD')||' exists');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD')||' exists');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'13 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'13 days'::interval, 'YYYYMMDD')||' does not exist');

SELECT col_is_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'));
SELECT col_is_pk('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), ARRAY['Col1'], 
    'Check for primary key in Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'));


SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'Partman_Basic', ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT'], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT'], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT'], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT'], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT'], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    ARRAY['SELECT'], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'));

SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'));

SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'));

SELECT reapply_privileges('Partman_Test.Time_Taptest_Table');

SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 'Partman_Basic', 
    ARRAY['SELECT','INSERT','UPDATE', 'DELETE'], 
    'Check Partman_Basic privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'));

SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'));
SELECT table_privs_are('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 'Partman_Revoke', 
    '{}'::text[], 'Check Partman_Revoke privileges of Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'));

SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'));
SELECT table_owner_is ('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 'Partman_Owner', 
    'Check that ownership change worked for Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'));

-- Test that maintenance will catch up
DO $$
BEGIN
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD')||'"';
    EXECUTE 'DROP TABLE "Partman_Test"."Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD')||'"';
END
$$;

SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD')||' does not exist');

SELECT run_maintenance();

SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 days'::interval, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 days'::interval, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||' does exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||' does not exist');

INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(11,20), CURRENT_TIMESTAMP + '1 day'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(21,25), CURRENT_TIMESTAMP + '2 days'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(26,30), CURRENT_TIMESTAMP + '3 days'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(1,10), CURRENT_TIMESTAMP);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(40,49), CURRENT_TIMESTAMP - '1 day'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(50,70), CURRENT_TIMESTAMP - '2 days'::interval);

SELECT run_maintenance();

SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD')||' does exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD')||' does not exist');

INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(31,37), CURRENT_TIMESTAMP + '4 days'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(101,122), CURRENT_TIMESTAMP + '5 days'::interval);
INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(123,150), CURRENT_TIMESTAMP + '6 days'::interval);

SELECT run_maintenance();

SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD')||' does exist');
SELECT has_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD')||' does exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'13 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'13 days'::interval, 'YYYYMMDD')||' does not exist');

INSERT INTO "Partman_Test"."Time_Taptest_Table" ("Col1", "Col3") VALUES (generate_series(200,210), CURRENT_TIMESTAMP + '20 days'::interval);
SELECT results_eq('SELECT count(*)::int FROM ONLY "Partman_Test"."Time_Taptest_Table_default"', ARRAY[11], 'Check that data outside scope goes to default');


SELECT drop_partition_time('Partman_Test.Time_Taptest_Table', '3 days', p_keep_table := false);
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'4 days'::interval, 'YYYYMMDD')||' does not exist');

UPDATE part_config SET retention = '2 days'::interval WHERE parent_table = 'Partman_Test.Time_Taptest_Table';
SELECT drop_partition_time('Partman_Test.Time_Taptest_Table', p_retention_schema := 'Partman_Retention_Test');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT has_table('Partman_Retention_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'3 days'::interval, 'YYYYMMDD')||' got moved to new schema');

SELECT undo_partition('Partman_Test.Time_Taptest_Table', p_loop_count => 20, p_target_table := 'Partman_Test.Undo_Taptest', p_keep_table := false);
SELECT results_eq('SELECT count(*)::int FROM  "Partman_Test"."Undo_Taptest"', ARRAY[129], 'Check count from target table after undo');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'1 day'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'2 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'3 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'4 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'5 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'6 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'7 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'8 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'9 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'10 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'11 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP+'12 days'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'1 day'::interval, 'YYYYMMDD')||' does not exist');
SELECT hasnt_table('Partman_Test', 'Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD'), 
    'Check Time_Taptest_Table_p'||to_char(CURRENT_TIMESTAMP-'2 days'::interval, 'YYYYMMDD')||' does not exist');

SELECT hasnt_table('partman', 'Template_Partman_Test_Time_Taptest_Table', 'Check that template table was dropped');


SELECT * FROM finish();
ROLLBACK;

