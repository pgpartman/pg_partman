-- See part1 for full notes

-- ########### WARNING WARNING WARNING ##############
-- Cannot run this test inside a transaction since then the BGW would not see this partition set exists
-- ########### WARNING WARNING WARNING ##############

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(5);

REVOKE USAGE ON SCHEMA partman FROM partman_owner;
REVOKE ALL ON ALL TABLES IN SCHEMA partman FROM partman_owner;
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA partman FROM partman_owner;
REVOKE EXECUTE ON ALL PROCEDURES IN SCHEMA partman FROM partman_owner;

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
