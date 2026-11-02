#!/bin/bash
set -e

# Bump max_locks_per_transaction for partman tests
echo "max_locks_per_transaction = 128" >> "$PGDATA/postgresql.conf"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE SCHEMA partman;
    CREATE EXTENSION pg_partman SCHEMA partman;
    CREATE EXTENSION pgtap;
EOSQL
