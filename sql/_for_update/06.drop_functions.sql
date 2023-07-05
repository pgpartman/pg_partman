-- Permanently dropped
DROP FUNCTION IF EXISTS @extschema@.apply_foreign_keys(text, text, bigint, boolean);
DROP FUNCTION IF EXISTS @extschema@.apply_publications(text, text, text);
DROP FUNCTION IF EXISTS @extschema@.create_function_id(text, bigint);
DROP FUNCTION IF EXISTS @extschema@.create_function_time(text, bigint);
DROP FUNCTION IF EXISTS @extschema@.create_trigger(text);
DROP FUNCTION IF EXISTS @extschema@.drop_partition_column(text, text);


-- Dropped and replaced
DROP FUNCTION @extschema@.check_subpart_sameconfig(text);
DROP FUNCTION @extschema@.create_parent(text, text, text, text, text[], int, text, text, boolean, text, text, text[], boolean, text, boolean, text);
DROP FUNCTION @extschema@.create_partition_id(text, bigint[], boolean, text);
DROP FUNCTION @extschema@.create_partition_time(text, timestamptz[], boolean, text);
DROP FUNCTION @extschema@.create_sub_parent(text, text, text, text, text, text[], int, text, boolean, text, text, boolean, boolean, text);
DROP FUNCTION @extschema@.run_maintenance(text, boolean, boolean);
DROP FUNCTION @extschema@.undo_partition(text, int, text, boolean, numeric, text, text[], boolean);
DROP PROCEDURE @extschema@.partition_data_proc (text, text, int, int, text, text, int, int, boolean, text[]);
DROP PROCEDURE @extschema@.run_maintenance_proc(int, boolean, boolean);
DROP PROCEDURE @extschema@.undo_partition_proc(text, text, int, int, text, boolean, int, int, boolean, text[], boolean);


