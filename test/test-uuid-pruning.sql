-- ########## UUID7 ENCODER/DECODER PRUNING TESTS ##########
-- Github Issue #873
-- A query filtered with uuid7_time_encoder() should only scan the matching child table.

\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path','partman, public',false);
-- Child boundaries are built in the session time zone and the queries below use UTC bounds
SET TimeZone = 'UTC';

SELECT plan(10);

CREATE SCHEMA partman_test;

SELECT volatility_is('partman', 'uuid7_time_encoder', ARRAY['timestamp with time zone'], 'immutable', 'Check uuid7_time_encoder() is immutable');
SELECT volatility_is('partman', 'uuid7_time_decoder', ARRAY['text'], 'immutable', 'Check uuid7_time_decoder() is immutable');
SELECT is(
    (SELECT array_agg(proparallel ORDER BY proname) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'partman' AND proname IN ('uuid7_time_encoder', 'uuid7_time_decoder'))
    , ARRAY['s','s']::"char"[]
    , 'Check uuid7 helper functions are parallel safe');

CREATE TABLE partman_test.uuid_pruning_table
    (col1 uuid NOT NULL
        , col2 text
        , CONSTRAINT uuid_pruning_table_pkey PRIMARY KEY (col1))
    PARTITION BY RANGE (col1);

SELECT create_partition(
    p_parent_table := 'partman_test.uuid_pruning_table'
    , p_control := 'col1'
    , p_interval := '1 month'
    , p_time_encoder := 'partman.uuid7_time_encoder'
    , p_time_decoder := 'partman.uuid7_time_decoder'
    , p_start_partition := '2026-01-01'
    , p_premake := 6
);

INSERT INTO partman_test.uuid_pruning_table (col1, col2)
SELECT uuid7_time_encoder(ts), ts::text
FROM generate_series('2026-01-15 00:00:00+00'::timestamptz, '2026-06-15 00:00:00+00'::timestamptz, '1 month') AS ts;

SELECT cmp_ok(
    (SELECT count(*)::int FROM pg_catalog.pg_inherits WHERE inhparent = 'partman_test.uuid_pruning_table'::regclass)
    , '>', 6, 'Check partition set has more than 6 child tables');

-- Capture the plan. Index and bitmap scans are off so each child shows up as one Seq Scan line.
SET enable_indexscan = off;
SET enable_indexonlyscan = off;
SET enable_bitmapscan = off;
CREATE TEMP TABLE uuid_pruning_plan (line text);
CREATE FUNCTION partman_test.capture_plan(p_query text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_line text;
BEGIN
    DELETE FROM uuid_pruning_plan;
    FOR v_line IN EXECUTE 'EXPLAIN (COSTS OFF) ' || p_query LOOP
        INSERT INTO uuid_pruning_plan VALUES (v_line);
    END LOOP;
END
$$;

SELECT partman_test.capture_plan($q$SELECT count(*) FROM partman_test.uuid_pruning_table
    WHERE col1 >= partman.uuid7_time_encoder('2026-03-01 00:00:00+00')
    AND col1 < partman.uuid7_time_encoder('2026-04-01 00:00:00+00')$q$);
SELECT is(
    (SELECT count(*)::int FROM uuid_pruning_plan WHERE line ~ 'Seq Scan on uuid_pruning_table_')
    , 1, 'Check query filtered with uuid7_time_encoder() is pruned to one child table');
SELECT is(
    (SELECT count(*)::int FROM uuid_pruning_plan WHERE line ~ 'Seq Scan on uuid_pruning_table_p20260301 ')
    , 1, 'Check the remaining child table is uuid_pruning_table_p20260301');
SELECT is(
    (SELECT count(*)::int FROM uuid_pruning_plan WHERE line ~ 'uuid7_time_encoder')
    , 0, 'Check uuid7_time_encoder() calls were folded to constants at plan time');

RESET enable_indexscan;
RESET enable_indexonlyscan;
RESET enable_bitmapscan;

SELECT results_eq(
    $q$SELECT col2 FROM partman_test.uuid_pruning_table
        WHERE col1 >= partman.uuid7_time_encoder('2026-03-01 00:00:00+00')
        AND col1 < partman.uuid7_time_encoder('2026-04-01 00:00:00+00')$q$
    , ARRAY[('2026-03-15 00:00:00+00'::timestamptz)::text]
    , 'Check pruned query still returns the matching row');

SELECT is(
    (SELECT count(*)::int FROM partman_test.uuid_pruning_table
        WHERE uuid7_time_decoder(col1::text) >= '2026-03-01 00:00:00+00'
        AND uuid7_time_decoder(col1::text) < '2026-05-01 00:00:00+00')
    , 2, 'Check uuid7_time_decoder() returns the encoded timestamps');

SELECT lives_ok(
    $q$CREATE INDEX uuid_pruning_table_decoded_idx ON partman_test.uuid_pruning_table (partman.uuid7_time_decoder(col1::text))$q$
    , 'Check uuid7_time_decoder() can be used in an index expression');

SELECT * FROM finish();
ROLLBACK;
