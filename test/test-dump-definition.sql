\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;

SELECT set_config('search_path','partman, public',false);

SELECT plan(4);

-- Sanity check that new features get add to definition dumping.
SELECT bag_eq(
  E'SELECT attname
    FROM pg_catalog.pg_attribute a
    JOIN pg_catalog.pg_class c ON a.attrelid = c.oid
    WHERE c.relname = ''part_config''
      AND NOT attisdropped AND attnum > 0',
  ARRAY[
    'parent_table',
    'control',
    'partition_interval',
    'partition_type',
    'premake',
    'automatic_maintenance',
    'template_table',
    'retention',
    'retention_schema',
    'retention_keep_index',
    'retention_keep_table',
    'epoch',
    'constraint_cols',
    'optimize_constraint',
    'infinite_time_partitions',
    'datetime_string',
    'jobmon',
    'sub_partition_set_full',
    'undo_in_progress',
    'inherit_privileges',
    'constraint_valid',
    'ignore_default_data',
    'default_table',
    'date_trunc_interval'
  ]::TEXT[],
  'When adding a new column to part_config please ensure it is also added to the dump_partitioned_table_definition function'
);


-- Create a partman declarative partitioned table.
CREATE TABLE public.declarative_objects(
  id SERIAL,
  t TEXT,
  created_at TIMESTAMP NOT NULL
) PARTITION BY RANGE (created_at);
SELECT create_parent('public.declarative_objects', 'created_at', '1 week', p_premake := 2, p_start_partition := (NOW() - '4 weeks'::INTERVAL)::TEXT);
-- Update config options you can't set at initial creation.
UPDATE part_config
SET retention='5 weeks', retention_keep_table = 'f', infinite_time_partitions = 't', constraint_valid = 'f', inherit_privileges = 't'
WHERE parent_table = 'public.declarative_objects';

-- Test output "visually" (with p_ignore_template_table = true).
SELECT dump_partitioned_table_definition('public.declarative_objects', p_ignore_template_table := true);
--
-- -- Test output "visually" (with default p_ignore_template_table = false).
-- -- Note that spaces before each line are literal tabs (\t), not spaces
SELECT is(
  (SELECT dump_partitioned_table_definition('public.declarative_objects')),
E'SELECT partman.create_parent(
	p_parent_table := ''public.declarative_objects'',
	p_control := ''created_at'',
	p_interval := ''7 days'',
	p_type := ''range'',
	p_epoch := ''none'',
	p_premake := 2,
	p_default_table := ''t'',
	p_automatic_maintenance := ''on'',
	p_constraint_cols := NULL,
	p_template_table := ''partman.template_public_declarative_objects'',
	p_jobmon := ''t'',
	p_date_trunc_interval := NULL
);
UPDATE partman.part_config SET
	optimize_constraint = 30,
	retention = ''5 weeks'',
	retention_schema = NULL,
	retention_keep_index = ''t'',
	retention_keep_table = ''f'',
	infinite_time_partitions = ''t'',
	datetime_string = ''YYYYMMDD'',
	sub_partition_set_full = ''f'',
	inherit_privileges = ''t'',
	constraint_valid = ''f'',
	ignore_default_data = ''t''
WHERE parent_table = ''public.declarative_objects'';'
);

-- Test end to end (with p_ignore_template_table = true):
-- 1. Capture the current config.
SELECT part_config AS declarative_objects_part_config FROM part_config WHERE parent_table = 'public.declarative_objects'
\gset
SELECT dump_partitioned_table_definition('public.declarative_objects', p_ignore_template_table := true) AS var_sql
\gset
-- 2. Remove partitioning and recreate table.
CREATE TABLE public.old_declarative_objects(id SERIAL, t TEXT, created_at TIMESTAMP NOT NULL);
SELECT undo_partition('public.declarative_objects', p_target_table := 'public.old_declarative_objects', p_keep_table := false);
DROP TABLE public.declarative_objects;
CREATE TABLE public.declarative_objects(
  id SERIAL,
  t TEXT,
  created_at TIMESTAMP NOT NULL
) PARTITION BY RANGE (created_at);
-- 3. Run dumped config.
SELECT :'var_sql'
\gexec
-- 4. Check the current config (it should match step 1).
SELECT row_eq(
  'SELECT * FROM part_config WHERE parent_table = ''public.declarative_objects''',
  (:'declarative_objects_part_config')::part_config
);

-- Test end to end (with default p_ignore_template_table = false):
-- 1. Capture the current config.
SELECT part_config AS declarative_objects_part_config FROM part_config WHERE parent_table = 'public.declarative_objects'
\gset
SELECT dump_partitioned_table_definition('public.declarative_objects') AS var_sql
\gset
-- 2. Remove partitioning and recreate table.
SELECT undo_partition('public.declarative_objects', p_target_table := 'public.old_declarative_objects', p_keep_table := false);
DROP TABLE public.declarative_objects;
CREATE TABLE public.declarative_objects(
  id SERIAL,
  t TEXT,
  created_at TIMESTAMP NOT NULL
) PARTITION BY RANGE (created_at);
-- 3. Run dumped config (after creating template table).
CREATE TABLE template_public_declarative_objects(
  id SERIAL,
  t TEXT,
  created_at TIMESTAMP NOT NULL
);
SELECT :'var_sql'
\gexec
-- 4. Check the current config (it should match step 1).
SELECT row_eq(
  'SELECT * FROM part_config WHERE parent_table = ''public.declarative_objects''',
  (:'declarative_objects_part_config')::part_config
);

SELECT * FROM finish();

ROLLBACK;
