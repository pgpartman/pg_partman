#! /bin/bash

cd /home/pg_partman

make && make install

psql -U postgres -c "DROP DATABASE IF EXISTS partman_test"
psql -U postgres -c "CREATE DATABASE partman_test"
psql -U postgres -d partman_test -c "CREATE EXTENSION pgtap"
psql -U postgres -d partman_test -c "CREATE SCHEMA partman"
psql -U postgres -d partman_test -c "CREATE EXTENSION pg_partman SCHEMA partman"
