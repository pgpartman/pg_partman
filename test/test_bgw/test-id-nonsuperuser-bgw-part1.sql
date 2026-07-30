-- ########## ID TESTS WITH BACKGROUND WORKER RUNNING ##########
-- Additional tests:
    -- turn off pg_jobmon logging
    -- UNLOGGED
    -- retention
    -- fk reference
-- Set the pg_partman_bgw.interval setting in postgresql.conf to 10 seconds (or less) in order for this test suite to pass successfully.
-- Test create_parent() alias
-- Test that BGW can run as a non-superuser. Requires creation of partman_maintainer role and that the BGW be running as that role
    -- Run in psql: CREATE ROLE partman_maintainer WITH LOGIN;
    -- Set in postgresql.conf: pg_partman_bgw.role = 'partman_maintainer'    
    -- Part1 must be run as a superuser
    -- Part2 can be run as partman_maintainer or partman_owner, but ideal as partman_owner for true testing that maintainer role can affect other role's partition sets
        -- Example call: pg_prove -U partman_maintainer -d keith -ovf test/test_bgw/test-id-nonsuperuser-bgw-part2.sql
    -- Part3 must be run as a superuser
-- ########### WARNING WARNING WARNING ##############
-- Cannot run this test inside a transaction since then the BGW would not see this partition set exists
-- ########### WARNING WARNING WARNING ##############

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

--BEGIN;
SELECT set_config('search_path','partman, public',false);

SELECT plan(5);


CREATE USER partman_basic;
CREATE USER partman_revoke;
CREATE USER partman_owner;
-- The maintainer role must have ownership privileges on the partition table sets
GRANT partman_owner TO partman_maintainer;

SELECT has_role('partman_maintainer', 'Check that partman_maintainer role exists');
SELECT has_role('partman_basic', 'Check that partman_basic role exists');
SELECT has_role('partman_revoke', 'Check that partman_revoke role exists');
SELECT has_role('partman_owner', 'Check that partman_owner role exists');
SELECT is_member_of('partman_owner', 'partman_maintainer', 'Check that partman_maintainer is a member of partman_owner');

GRANT ALL ON SCHEMA partman TO partman_maintainer;
GRANT ALL ON ALL TABLES IN SCHEMA partman TO partman_maintainer;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA partman TO partman_maintainer;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA partman TO partman_maintainer;

GRANT USAGE ON SCHEMA partman TO partman_owner;
GRANT ALL ON ALL TABLES IN SCHEMA partman TO partman_owner;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA partman TO partman_owner;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA partman TO partman_owner;

CREATE SCHEMA partman_test AUTHORIZATION partman_owner;
CREATE SCHEMA partman_retention_test AUTHORIZATION partman_owner;

-- TODO add tests that above stuff was created so pgtap can run this cleanly. See procedure tests for text output instruction example
DO $$
BEGIN
EXECUTE format('GRANT temporary on database %I TO partman_maintainer', current_database());
END
$$;

SELECT * FROM finish();
--ROLLBACK;
