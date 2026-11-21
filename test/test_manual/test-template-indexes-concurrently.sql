-- Run with psql in autocommit mode after installing pg_partman in schema partman.
-- Concurrent DDL cannot run inside the rolled-back pgTAP tests.
\set ON_ERROR_STOP true

CREATE SCHEMA partman_template_concurrent_test;
CREATE TABLE partman_template_concurrent_test.parent (id bigint NOT NULL, payload text)
    PARTITION BY RANGE (id);
CREATE TABLE partman_template_concurrent_test.template
    (LIKE partman_template_concurrent_test.parent);
CREATE INDEX ON partman_template_concurrent_test.template (payload);
SELECT partman.create_partition('partman_template_concurrent_test.parent', 'id', '10',
    p_start_partition := '0', p_premake := 1,
    p_template_table := 'partman_template_concurrent_test.template', p_jobmon := false);
INSERT INTO partman_template_concurrent_test.parent VALUES (1, 'range'), (100, 'default');

DO $$
BEGIN
    IF (SELECT count(*) FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'partman_template_concurrent_test' AND c.relispartition) <> 3 THEN
        RAISE EXCEPTION 'Missing template indexes';
    END IF;
    IF EXISTS (SELECT FROM pg_inherits h JOIN pg_class c ON c.oid = h.inhrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'partman_template_concurrent_test' AND c.relkind = 'i') THEN
        RAISE EXCEPTION 'Attached template indexes';
    END IF;
END
$$;

SELECT format('DROP INDEX CONCURRENTLY %I.%I', n.nspname, idx.relname)
FROM pg_index i JOIN pg_class idx ON idx.oid = i.indexrelid
JOIN pg_class child ON child.oid = i.indrelid
JOIN pg_namespace n ON n.oid = idx.relnamespace
WHERE n.nspname = 'partman_template_concurrent_test' AND child.relispartition
\gexec

DO $$
BEGIN
    IF EXISTS (SELECT FROM pg_index i JOIN pg_class c ON c.oid = i.indrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'partman_template_concurrent_test' AND c.relispartition) THEN
        RAISE EXCEPTION 'Remaining child indexes';
    END IF;
    IF (SELECT count(*) FROM partman_template_concurrent_test.parent) <> 2 THEN
        RAISE EXCEPTION 'Missing partition data';
    END IF;
END
$$;

SELECT partman.config_cleanup('partman_template_concurrent_test.parent');
DROP SCHEMA partman_template_concurrent_test CASCADE;
