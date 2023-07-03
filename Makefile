EXTENSION = pg_partman
EXTVERSION = $(shell grep default_version $(EXTENSION).control | \
               sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")

PG_CONFIG = pg_config
PG_VER = $(shell $(PG_CONFIG) --version | sed "s/^[^ ]* \([0-9]*\).*$$/\1/" 2>/dev/null)

PG_VER_min = 14

ifeq ($(shell expr "$(PG_VER_min)" \<=  "$(PG_VER)"), 0)
$(error Minimum version of PostgreSQL required is $(PG_VER_min) (but have $(PG_VER)))
endif

DOCS = $(wildcard doc/*.md)
MODULES = src/pg_partman_bgw

# If user does not want the background worker, run: make NO_BGW=1
ifneq ($(NO_BGW),)
	MODULES=
endif

.PHONY: all
all: sql/$(EXTENSION)--$(EXTVERSION).sql

SCRIPTS = bin/common/*.py

sql/$(EXTENSION)--$(EXTVERSION).sql: $(wildcard sql/types/*.sql sql/tables/*.sql sql/functions/*.sql sql/procedures/*.sql)
	cat $^ > $@

DATA = $(wildcard updates/*--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql
EXTRA_CLEAN = sql/$(EXTENSION)--$(EXTVERSION).sql

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
