#!/bin/sh


echo "Install and start a simple PostgreSQL cluster for testing"


initdb -D /tmp/pgtest
echo "shared_preload_libraries = 'pg_partman_bgw'" >/tmp/pgtest/postgresql.conf

pg_ctl -D /tmp/pgtest start

echo "Postgres started; wait for startup.";
sleep 2

psql -c 'CREATE SCHEMA partman; CREATE EXTENSION IF NOT EXISTS pg_partman SCHEMA partman; CREATE EXTENSION IF NOT EXISTS pgtap;' postgres


echo "Postgres running (unless there are error mesages). Start testing with"
echo 
echo "  pg_prove -d postgres -ovf tests/*.sql"
echo 
echo "stop all with: pg_ctl -D /tmp/pgtest stop && rm -rvf /tmp/pgtest"

test/test-id-id-id-subpart.sql            (Wstat: 768 Tests: 1508 Failed: 0)
  Non-zero exit status: 3
  Parse errors: Bad plan.  You planned 3096 tests but ran 1508.
test/test-time-weekly-daily-subpart.sql   (Wstat: 0 Tests: 278 Failed: 4)
  Failed tests:  169-171, 173