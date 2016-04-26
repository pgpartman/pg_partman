#
# Install and start a simple test cluster  
#

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

