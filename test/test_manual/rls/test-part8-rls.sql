-- Additional tests: Testing nonsuperuser

-- NOTE: THIS FILE MUST BE RUN AS A SUPERUSER

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(1);

DO $$
BEGIN
EXECUTE format('REVOKE temporary on database %I FROM partman_maintenance', current_database());
END
$$;

DROP SCHEMA IF EXISTS partman_test CASCADE;

SELECT hasnt_schema('partman_test', 'Check that test schema was dropped');

DROP POLICY part_config_test_user_access_policy ON part_config;
DROP POLICY part_config_test_maintenance_access_policy ON part_config;

REVOKE ALL ON SCHEMA partman FROM partman_alpha, partman_beta, partman_maintenance;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA partman FROM partman_alpha, partman_beta, partman_maintenance;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA partman FROM partman_alpha, partman_beta, partman_maintenance;
REVOKE ALL ON ALL TABLES IN SCHEMA partman FROM partman_alpha, partman_beta, partman_maintenance;

DROP ROLE IF EXISTS partman_alpha;
DROP ROLE IF EXISTS partman_beta;
DROP ROLE IF EXISTS partman_maintenance;


ALTER TABLE part_config DISABLE ROW LEVEL SECURITY;

SELECT * FROM finish();
