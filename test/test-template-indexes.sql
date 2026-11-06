-- Template indexes stay independent unless the parent supplies a matching index.
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path', 'partman, public', false);
SELECT plan(15);
CREATE SCHEMA partman_test;

CREATE TABLE partman_test.template_index_parent (
    id bigint NOT NULL UNIQUE, payload text NOT NULL, extra integer, tags text[], span int4range
) PARTITION BY RANGE (id);
CREATE INDEX ON partman_test.template_index_parent (extra);
CREATE TABLE partman_test.template_indexes (LIKE partman_test.template_index_parent);
ALTER TABLE partman_test.template_indexes ADD PRIMARY KEY (payload);
CREATE INDEX ON partman_test.template_indexes (extra);
CREATE UNIQUE INDEX ON partman_test.template_indexes (extra);
CREATE INDEX ON partman_test.template_indexes (id);
CREATE INDEX ON partman_test.template_indexes (lower(payload) text_pattern_ops)
    INCLUDE (extra) WITH (fillfactor = 70) TABLESPACE pg_default WHERE extra > 0;
CREATE INDEX ON partman_test.template_indexes USING gin (tags) WITH (fastupdate = off);
ALTER TABLE partman_test.template_indexes ADD EXCLUDE USING gist (span WITH &&);
CREATE INDEX template_invalid ON partman_test.template_indexes (extra, payload);
UPDATE pg_index SET indisvalid = false
WHERE indexrelid = 'partman_test.template_invalid'::regclass;

SELECT create_partition('partman_test.template_index_parent', 'id', '10',
    p_start_partition := '0', p_premake := 1,
    p_template_table := 'partman_test.template_indexes', p_jobmon := false);

SELECT is((SELECT count(*)::integer FROM pg_index
    WHERE indrelid = 'partman_test.template_index_parent_p0'::regclass), 7,
    'Range partition has template indexes and no duplicate parent indexes');
SELECT is((SELECT count(*)::integer FROM pg_index
    WHERE indrelid = 'partman_test.template_index_parent_default'::regclass), 7,
    'Default partition has template indexes and no duplicate parent indexes');
SELECT is((SELECT count(*)::integer FROM pg_index i JOIN pg_inherits h ON h.inhrelid = i.indexrelid
    WHERE i.indrelid = 'partman_test.template_index_parent_p0'::regclass), 2,
    'Only the two parent indexes are attached');
SELECT is((SELECT count(*)::integer FROM pg_index
    WHERE indrelid = 'partman_test.template_index_parent_p0'::regclass AND indisunique), 3,
    'Template primary key and unique index survive alongside the parent unique index');

CREATE TEMP VIEW expected_template_indexes AS
SELECT indisunique, substring(pg_get_indexdef(indexrelid) FROM ' USING .*') AS definition
FROM pg_index WHERE indrelid = 'partman_test.template_indexes'::regclass
    AND indisvalid AND NOT indisexclusion
UNION
SELECT indisunique, substring(pg_get_indexdef(indexrelid) FROM ' USING .*')
FROM pg_index WHERE indrelid = 'partman_test.template_index_parent'::regclass;

SELECT results_eq($$SELECT indisunique, substring(pg_get_indexdef(indexrelid) FROM ' USING .*')
    FROM pg_index WHERE indrelid = 'partman_test.template_index_parent_p0'::regclass
    ORDER BY 1, 2$$, $$SELECT * FROM expected_template_indexes ORDER BY 1, 2$$,
    'Index methods, expressions, opclasses, INCLUDE, predicates and storage options are preserved');
SELECT results_eq($$SELECT indisunique, substring(pg_get_indexdef(indexrelid) FROM ' USING .*')
    FROM pg_index WHERE indrelid = 'partman_test.template_index_parent_default'::regclass
    ORDER BY 1, 2$$, $$SELECT * FROM expected_template_indexes ORDER BY 1, 2$$,
    'Default partition preserves index definitions');

INSERT INTO partman_test.template_index_parent (id, payload, extra) VALUES (19, 'one', 1);
SELECT run_maintenance('partman_test.template_index_parent', p_jobmon := false);
SELECT has_table('partman_test', 'template_index_parent_p20', 'Maintenance creates a partition');
SELECT results_eq($$SELECT indisunique, substring(pg_get_indexdef(indexrelid) FROM ' USING .*')
    FROM pg_index WHERE indrelid = 'partman_test.template_index_parent_p20'::regclass
    ORDER BY 1, 2$$, $$SELECT * FROM expected_template_indexes ORDER BY 1, 2$$,
    'Maintenance copies template indexes');

CREATE TABLE partman_test.template_list_parent (id bigint NOT NULL, payload text)
    PARTITION BY LIST (id);
CREATE TABLE partman_test.template_list (LIKE partman_test.template_list_parent);
CREATE INDEX ON partman_test.template_list (payload);
SELECT create_partition('partman_test.template_list_parent', 'id', '1', 'list',
    p_start_partition := '0', p_premake := 1,
    p_template_table := 'partman_test.template_list', p_jobmon := false);
SELECT is_indexed('partman_test', 'template_list_parent_p0', 'payload',
    'List partition copies non-unique template index');
SELECT is((SELECT count(*)::integer FROM pg_index i JOIN pg_inherits h ON h.inhrelid = i.indexrelid
    WHERE i.indrelid = 'partman_test.template_list_parent_p0'::regclass), 0,
    'List partition template index is independent');

CREATE TABLE partman_test.template_time_parent (created_at timestamptz NOT NULL, payload text)
    PARTITION BY RANGE (created_at);
CREATE TABLE partman_test.template_time (LIKE partman_test.template_time_parent);
CREATE INDEX ON partman_test.template_time (payload);
SELECT create_partition('partman_test.template_time_parent', 'created_at', '1 day',
    p_premake := 1, p_template_table := 'partman_test.template_time', p_jobmon := false);
SELECT ok(NOT EXISTS (
    SELECT FROM show_partitions('partman_test.template_time_parent', p_include_default := true) p
    WHERE NOT EXISTS (SELECT FROM pg_index i
        WHERE i.indrelid = format('%I.%I', p.partition_schemaname, p.partition_tablename)::regclass)
), 'Every time partition, including the default, copies the template index');
SELECT is((SELECT count(*)::integer FROM pg_index i JOIN pg_inherits h ON h.inhrelid = i.indexrelid
    WHERE i.indrelid = 'partman_test.template_time_parent_default'::regclass), 0,
    'Default time partition template index is independent');

-- A partitioned child gets its indexes from its own leaf partitions.
CREATE TABLE partman_test.template_subparent (id bigint NOT NULL) PARTITION BY RANGE (id);
SELECT is(inherit_template_properties('partman_test.template_list_parent', 'partman_test',
    'template_subparent'), false, 'Template properties are skipped on subpartition parents');
SELECT is((SELECT count(*)::integer FROM pg_index
    WHERE indrelid = 'partman_test.template_subparent'::regclass), 0,
    'Subpartition parent has no template indexes');
SELECT is((SELECT count(*)::integer FROM pg_index
    WHERE indrelid = 'partman_test.template_index_parent'::regclass), 2,
    'Template index copying does not add indexes to the parent');

SELECT * FROM finish();
ROLLBACK;
