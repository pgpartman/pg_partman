EXTENSION = pg_partman
EXTVERSION = $(shell grep default_version $(EXTENSION).control | \
               sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")

PG_CONFIG = pg_config
PG14 = $(shell $(PG_CONFIG) --version | egrep " 13\." > /dev/null && echo no || echo yes)

ifeq ($(PG14),yes)

DOCS = $(wildcard doc/*.md)
MODULES = src/pg_partman_bgw

# If user does not want the background worker, run: make NO_BGW=1
ifneq ($(NO_BGW),)
	MODULES=
endif

all: sql/$(EXTENSION)--$(EXTVERSION).sql

SCRIPTS = bin/common/*.py

sql/$(EXTENSION)--$(EXTVERSION).sql: $(sort $(wildcard sql/types/*.sql)) $(sort $(wildcard sql/tables/*.sql)) $(sort $(wildcard sql/functions/*.sql)) $(sort $(wildcard sql/procedures/*.sql))
	cat $^ > $@

DATA = $(wildcard updates/*--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql
EXTRA_CLEAN = sql/$(EXTENSION)--$(EXTVERSION).sql
else
$(error Minimum version of PostgreSQL required is 9.4.0)

# end PG14 if
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
