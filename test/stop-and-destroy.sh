#!/bin/sh

echo "Stop Test-PostgresSQL and destroy cluster"

pg_ctl -D /tmp/pgtest -m fast stop
rm -rvf /tmp/pgtest

