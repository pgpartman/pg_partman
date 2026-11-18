-- ########## ID TEMPLATE EXCLUSION CONSTRAINT TESTS ##########
-- Additional tests:
    -- partition key is an expression, so primary key and exclusion constraint can only be set on the template table
    -- exclusion constraint on the template table is created on initial children, the default and children made by maintenance
    -- exclusion constraint is enforced on the child tables

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(14);
CREATE SCHEMA partman_test;

CREATE TABLE partman_test.id_taptest_table
    (col1 text NOT NULL
        , col2 int4range NOT NULL CHECK (NOT isempty(col2))
        , col3 int4 GENERATED ALWAYS AS (upper(col2)) STORED)
    PARTITION BY RANGE (upper(col2));

CREATE TABLE partman_test.template_id_taptest_table
    (LIKE partman_test.id_taptest_table INCLUDING ALL
        , PRIMARY KEY (col1, col2)
        , EXCLUDE USING gist (col2 WITH &&));

SELECT create_partition('partman_test.id_taptest_table', 'col3', '30', p_premake := 2, p_control_not_null := false, p_template_table := 'partman_test.template_id_taptest_table');

SELECT has_table('partman_test', 'id_taptest_table_p0', 'Check id_taptest_table_p0 exists');
SELECT has_table('partman_test', 'id_taptest_table_p30', 'Check id_taptest_table_p30 exists');
SELECT has_table('partman_test', 'id_taptest_table_p60', 'Check id_taptest_table_p60 exists');
SELECT has_table('partman_test', 'id_taptest_table_default', 'Check id_taptest_table_default exists');

SELECT col_is_pk('partman_test', 'id_taptest_table_p0', ARRAY['col1','col2'], 'Check for primary key in id_taptest_table_p0');

SELECT is((SELECT count(*)::int FROM pg_catalog.pg_constraint WHERE conrelid = 'partman_test.id_taptest_table_p0'::regclass AND contype = 'x'), 1, 'Check for exclusion constraint in id_taptest_table_p0');
SELECT is((SELECT count(*)::int FROM pg_catalog.pg_constraint WHERE conrelid = 'partman_test.id_taptest_table_p30'::regclass AND contype = 'x'), 1, 'Check for exclusion constraint in id_taptest_table_p30');
SELECT is((SELECT count(*)::int FROM pg_catalog.pg_constraint WHERE conrelid = 'partman_test.id_taptest_table_p60'::regclass AND contype = 'x'), 1, 'Check for exclusion constraint in id_taptest_table_p60');
SELECT is((SELECT count(*)::int FROM pg_catalog.pg_constraint WHERE conrelid = 'partman_test.id_taptest_table_default'::regclass AND contype = 'x'), 1, 'Check for exclusion constraint in id_taptest_table_default');

INSERT INTO partman_test.id_taptest_table (col1, col2) VALUES ('stuff', int4range(1, 10));
SELECT throws_ok($$INSERT INTO partman_test.id_taptest_table (col1, col2) VALUES ('other stuff', int4range(5, 15))$$, '23P01', NULL, 'Check that exclusion constraint is enforced in id_taptest_table_p0');

INSERT INTO partman_test.id_taptest_table (col1, col2) VALUES ('stuff', int4range(61, 70));
SELECT run_maintenance();

SELECT has_table('partman_test', 'id_taptest_table_p90', 'Check id_taptest_table_p90 exists');
SELECT has_table('partman_test', 'id_taptest_table_p120', 'Check id_taptest_table_p120 exists');
SELECT is((SELECT count(*)::int FROM pg_catalog.pg_constraint WHERE conrelid = 'partman_test.id_taptest_table_p90'::regclass AND contype = 'x'), 1, 'Check for exclusion constraint in id_taptest_table_p90');
SELECT is((SELECT count(*)::int FROM pg_catalog.pg_constraint WHERE conrelid = 'partman_test.id_taptest_table_p120'::regclass AND contype = 'x'), 1, 'Check for exclusion constraint in id_taptest_table_p120');

SELECT * FROM finish();
ROLLBACK;
