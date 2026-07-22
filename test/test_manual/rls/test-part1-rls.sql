-- ########## TIME HOURLY TESTS ##########
-- Additional tests: Testing RLS and nonsuperuser

-- DO NOT RUN THIS TEST IN PRODUCTION!!!!
-- This test will enable RLS on the part_config table. This will lock out ALL other users from the part_config table except if the "maintenance_role" column is set and that is the role that is running maintenance.
-- Also, if you do have the RLS policy in place for the partman tables, the final part of this RLS test suite WILL DISABLE RLS on the part_config table
-- DO NOT RUN THIS TEST IN PRODUCTION!!!!

-- NOTE: THIS FILE MUST BE RUN AS A SUPERUSER

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

SELECT set_config('search_path','partman, public',false);

SELECT plan(6);

CREATE SCHEMA partman_test;
CREATE ROLE partman_alpha WITH LOGIN;
CREATE ROLE partman_beta WITH LOGIN;
CREATE ROLE partman_maintenance WITH LOGIN;
GRANT partman_alpha, partman_beta TO partman_maintenance;
DO $$
BEGIN
EXECUTE format('GRANT temporary on database %I TO partman_maintenance', current_database());
END
$$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA partman TO partman_alpha, partman_beta, partman_maintenance;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA partman TO partman_alpha, partman_beta, partman_maintenance;
GRANT ALL ON ALL TABLES IN SCHEMA partman TO partman_alpha, partman_beta, partman_maintenance;

GRANT ALL ON SCHEMA partman TO partman_alpha, partman_beta, partman_maintenance;
GRANT ALL ON SCHEMA partman_test TO partman_alpha, partman_beta, partman_maintenance;

ALTER TABLE part_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY part_config_test_user_access_policy ON part_config 
    FOR ALL 
    TO PUBLIC 
    USING (maintenance_role = current_user)
    WITH CHECK (maintenance_role = current_user); 

CREATE POLICY part_config_test_maintenance_access_policy ON part_config 
    FOR ALL 
    TO partman_maintenance
    USING (true);

SELECT has_schema('partman_test', 'Check that test schema exits');
SELECT has_role('partman_maintenance', 'Check that partman_maintenance role exists');
SELECT has_role('partman_alpha', 'Check that partman_alpha role exists');
SELECT has_role('partman_beta', 'Check that partman_beta role exists');
SELECT is_member_of('partman_alpha', 'partman_maintenance', 'Check that partman_maintenance is a member of partman_alpha');
SELECT is_member_of('partman_beta', 'partman_maintenance', 'Check that partman_maintenance is a member of partman_beta');


SELECT * FROM finish();
