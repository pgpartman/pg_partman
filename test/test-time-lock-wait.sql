-- Exercise the positive lock-wait branch with nonempty DEFAULT and source tables.
\set ON_ERROR_ROLLBACK 1
\set ON_ERROR_STOP true

BEGIN;
SELECT set_config('search_path', 'partman, public', false);
SELECT set_config('TimeZone', 'UTC', true);
SELECT plan(14);

CREATE SCHEMA "Partman Lock Test";
CREATE TABLE "Partman Lock Test"."Monthly Data" (
    id integer NOT NULL,
    payload text NOT NULL,
    "Expires On" timestamptz NOT NULL
) PARTITION BY RANGE ("Expires On");

SELECT create_partition('Partman Lock Test.Monthly Data', 'Expires On', '1 month');

INSERT INTO "Partman Lock Test"."Monthly Data" VALUES
    (1, 'first month', (date_trunc('month', CURRENT_TIMESTAMP) + interval '2 years')::date),
    (2, 'second month', (date_trunc('month', CURRENT_TIMESTAMP) + interval '2 years 1 month')::date);

SELECT is((SELECT count(*) FROM ONLY "Partman Lock Test"."Monthly Data_default"),
    2::bigint, 'Future rows initially route to DEFAULT');
SELECT is(partition_data_time('Partman Lock Test.Monthly Data', p_lock_wait := 2),
    1::bigint, 'Positive lock wait migrates the first monthly batch');
SELECT is((SELECT count(*) FROM ONLY "Partman Lock Test"."Monthly Data_default"),
    1::bigint, 'The upper bound leaves the second month in DEFAULT');
SELECT is(partition_data_time('Partman Lock Test.Monthly Data', p_lock_wait := 2, p_order := 'DESC'),
    1::bigint, 'Positive lock wait also works in descending order');
SELECT is((SELECT count(*) FROM ONLY "Partman Lock Test"."Monthly Data_default"),
    0::bigint, 'DEFAULT is empty after both batches');
SELECT is((SELECT count(*) FROM "Partman Lock Test"."Monthly Data"),
    2::bigint, 'The parent still exposes both rows');
SELECT results_eq('SELECT id, payload FROM "Partman Lock Test"."Monthly Data" ORDER BY id',
    $$VALUES (1, 'first month'::text), (2, 'second month'::text)$$,
    'Migration preserves row values');

CREATE TABLE "Partman Lock Test"."Source Data" (LIKE "Partman Lock Test"."Monthly Data");
INSERT INTO "Partman Lock Test"."Source Data" VALUES
    (3, 'source row', (date_trunc('month', CURRENT_TIMESTAMP) + interval '2 years 2 months')::date);
SELECT is(partition_data_time('Partman Lock Test.Monthly Data', p_lock_wait := 2,
    p_source_table := 'Partman Lock Test.Source Data'),
    1::bigint, 'Positive lock wait also migrates an explicit source table');
SELECT is((SELECT count(*) FROM "Partman Lock Test"."Source Data"),
    0::bigint, 'The explicit source is drained');
SELECT is((SELECT count(*) FROM "Partman Lock Test"."Monthly Data"),
    3::bigint, 'Source migration adds the row to the parent');

INSERT INTO "Partman Lock Test"."Monthly Data" VALUES
    (4, 'zero wait row', (date_trunc('month', CURRENT_TIMESTAMP) + interval '2 years 3 months')::date);
SELECT is((SELECT count(*) FROM ONLY "Partman Lock Test"."Monthly Data_default"),
    1::bigint, 'A new future row routes to DEFAULT');
SELECT is(partition_data_time('Partman Lock Test.Monthly Data', p_lock_wait := 0),
    1::bigint, 'Zero lock wait remains functional');
SELECT is((SELECT count(*) FROM ONLY "Partman Lock Test"."Monthly Data_default"),
    0::bigint, 'Zero lock wait drains DEFAULT');
SELECT is((SELECT count(*) FROM "Partman Lock Test"."Monthly Data"),
    4::bigint, 'All four rows remain visible through the parent');

SELECT * FROM finish();
ROLLBACK;
