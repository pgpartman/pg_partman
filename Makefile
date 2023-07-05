EXTENSION = pg_partman
EXTVERSION = $(shell grep default_version $(EXTENSION).control | \
               sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")

PREV_VERSION := 4.7.3

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
all: \
	updates/$(EXTENSION)--$(PREV_VERSION)--$(EXTVERSION).sql \
	sql/$(EXTENSION)--$(EXTVERSION).sql

SCRIPTS = bin/common/*.py

sql/$(EXTENSION)--$(EXTVERSION).sql: $(wildcard sql/types/*.sql sql/tables/*.sql sql/functions/*.sql sql/procedures/*.sql)
	cat $^ > $@


# Migration script

FUNCS_DIR := sql/functions
PROCS_DIR := sql/procedures
TABLS_DIR := sql/tables
INTRM_DIR := sql/_for_update

NEW_FUNCS := calculate_time_partition_info.sql

REPLACE_FUNCS_FILES := \
	apply_constraints.sql \
	check_default.sql \
	drop_partition_id.sql \
	drop_partition_time.sql \
	dump_partitioned_table_definition.sql \
	inherit_template_properties.sql \
	partition_data_id.sql \
	partition_data_time.sql \
	show_partition_info.sql \
	show_partition_name.sql \
	show_partitions.sql

RENEW_FUNCS_FILES := \
	check_subpart_sameconfig.sql \
	create_parent.sql \
	create_partition_id.sql \
	create_partition_time.sql \
	create_sub_parent.sql \
	run_maintenance.sql \
	undo_partition.sql

RENEW_PROCS_FILES := \
	partition_data_proc.sql \
	run_maintenance_proc.sql \
	undo_partition_proc.sql

$(INTRM_DIR)/51.%.repl.sql: $(FUNCS_DIR)/%.sql
	sed '1s/^CREATE FUNCTION /CREATE OR REPLACE FUNCTION /' $< > $@
	echo -e '\n' >> $@ # Add two empty lines in the end

# TEMPORARY: required to check existing migration is not touched. Later will be moved to parent rule.
$(INTRM_DIR)/51.%.orig.sql: $(FUNCS_DIR)/%.sql
	cp $< $@
	echo -e '\n' >> $@ # Add two empty lines in the end

# TEMPORARY: required to check existing migration is not touched. Later will be moved to parent rule.
$(INTRM_DIR)/52.%.orig.sql: $(PROCS_DIR)/%.sql
	cp $< $@
	echo -e '\n' >> $@ # Add two empty lines in the end


# TEMPORARY: Replaced and just created functions are required in a shared sorted order.
FUNC_ALL_FILES := $(sort \
	$(patsubst %.sql,$(INTRM_DIR)/51.%.repl.sql,$(REPLACE_FUNCS_FILES)) \
	$(patsubst %.sql,$(INTRM_DIR)/51.%.orig.sql,$(RENEW_FUNCS_FILES)) \
)

PROC_ALL_FILES := $(sort \
	$(patsubst %.sql,$(INTRM_DIR)/52.%.orig.sql,$(RENEW_PROCS_FILES)) \
)

# TEMPORARY: hard to read; required to check existing migration is not touched; later will be simplified.
updates/$(EXTENSION)--$(PREV_VERSION)--$(EXTVERSION).sql: | \
		$(INTRM_DIR)/01.tables.sql \
		$(TABLS_DIR)/part_config.sql \
		$(TABLS_DIR)/part_config_sub.sql \
		$(INTRM_DIR)/04.tables-copy-back.sql \
		$(INTRM_DIR)/08.hdr_new_functions.sql \
		$(addprefix $(FUNCS_DIR)/,$(NEW_FUNCS)) \
		$(INTRM_DIR)/08.hdr_altr_functions.sql \
		$(INTRM_DIR)/06.drop_functions.sql \
		$(FUNC_ALL_FILES) \
		$(INTRM_DIR)/08.hdr_altr_procedures.sql \
		$(PROC_ALL_FILES) \
		$(INTRM_DIR)/09.cleanup_temp.sql \
	# Begin rule body:
	cat $| > $@

# End of migration script


DATA = $(wildcard updates/*--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql
EXTRA_CLEAN = \
	sql/$(EXTENSION)--$(EXTVERSION).sql \
	updates/$(EXTENSION)--$(PREV_VERSION)--$(EXTVERSION).sql \
	$(FUNC_ALL_FILES) $(PROC_ALL_FILES)

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
