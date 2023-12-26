-- IMPORTANT NOTE: The initial version of pg_partman 5 had to be split into two updates due to changing both the data in the config table as well as adding constraints on that data. Depending on the data contained in the config table, doing this in a single-transaction update may not work (you may see an error about pending trigger events). If this is the case, please update to version 5.0.1 in a separate transaction from your update to 5.0.0. Example:

    /*
        BEGIN;
        ALTER EXTENSION pg_partman UPDATE TO '5.0.0';
        COMMIT;

        BEGIN;
        ALTER EXTENSION pg_partman UPDATE TO '5.0.1';
        COMMIT;
    */

-- Update 5.0.1 MUST be installed for version 5.x of pg_partman to work properly. As long as these updates are run within a few seconds of each other, there should be no issues.


ALTER TABLE @extschema@.part_config_sub ALTER CONSTRAINT part_config_sub_sub_parent_fkey DEFERRABLE INITIALLY DEFERRED;
