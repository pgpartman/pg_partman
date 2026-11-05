# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

pg_partman is a PostgreSQL extension (PL/pgSQL functions/procedures + a C background worker) that manages
time-based and ID-based declarative partition sets: creating child partitions ahead of time, applying
retention policies, migrating existing tables into partitioning, and running all of this automatically via
a background worker (BGW) or an external scheduler. Minimum supported PostgreSQL version is 14 (see
`Makefile`'s `PG_VER_min` and `META.json`).

## Build

```sh
make install            # builds sql/pg_partman--<version>.sql and installs, including the BGW
make NO_BGW=1 install   # skip compiling/installing the background worker, PL/pgSQL only
```

`PG_CONFIG` must point at the target `pg_config` (defaults to whatever is on `PATH`). The extension version
comes from `pg_partman.control`'s `default_version`.

Do not hand-edit `sql/pg_partman--<version>.sql` — it's a generated concatenation (see Architecture below)
and is also in `EXTRA_CLEAN`, so `make clean` removes it.

## Lint

```sh
make lint   # runs pre-commit (see .pre-commit-config.yaml): merge-conflict/yaml checks, EOF fixer,
            # line-ending fixer, trailing-whitespace, codespell
```

## Tests

Tests are pgTAP (`.sql` files), not a PL/pgSQL-only harness — pgTAP >= 1.2.0 must be installed. Full details
in `test/README_test.md`; the essentials:

- **`max_locks_per_transaction` must be raised above the default 64** (128 has worked) before running the
  suite — subpartitioning tests create/drop hundreds of tables in one transaction and can crash the cluster
  otherwise.
- Tests assume `pg_partman` is installed to schema `partman` and pgTAP to `public`; each test file has a
  config block at the top if a different setup is needed.
- Run the whole top-level suite with `pg_prove` (rolled back in a transaction, so side-effect free except
  jobmon logging if pg_jobmon is installed):
  ```sh
  pg_prove -ovf /path/to/pg_partman/test/*.sql
  ```
- Run a single test the same way, just pass one file: `pg_prove -ovf test/test-time-daily.sql`.
- Subfolders are **not** part of the "run everything" wildcard and need manual handling:
  - `test/test_bgw/` — background worker tests; read the header comment in each file for the
    `postgresql.conf` settings it requires first.
  - `test/test_procedure/` — tests for the `*_proc` procedures, split into numbered `-partN` files that must
    be run in order with manual commits between them (pgTAP can't span distinct transactions in one run).
  - `test/test_manual/`, `test/test_nonsuperuser/`, `test/test_no_search_path/`, `test/test_tablespace/` —
    scenario-specific setups, read each file before running.
  - `test/not_working_yet/` — known-broken/in-progress tests, not expected to pass.
- CI (`.github/workflows/ci.yml`) runs this matrix against PostgreSQL 14–18 using `pgxn/pgxn-tools`,
  installing into the `partman` schema and running `pg_prove` over the top-level `test` folder only.

## Architecture

**SQL build pipeline.** The installable extension script is assembled, not hand-written:
`sql/pg_partman--<version>.sql` = concatenation of `sql/types/*.sql`, `sql/tables/*.sql`,
`sql/functions/*.sql`, `sql/procedures/*.sql`, in that order (see the `Makefile` rule). Table/type
definitions and the constraint-check functions that reference them live in `sql/tables/tables.sql` together
(functions have to be created before the `ALTER TABLE ... ADD CONSTRAINT` that uses them, but after the
table itself — ordering across separate files would be harder to control, hence they're combined there
instead of under `sql/functions/`). Version upgrades between releases are hand-written diff scripts in
`updates/pg_partman--X.Y.Z--A.B.C.sql`, applied via `ALTER EXTENSION pg_partman UPDATE TO`.

**Configuration tables.** `part_config` (one row per managed parent/partitioned table) and `part_config_sub`
(one row per sub-partition template, FK'd to `part_config.parent_table`) hold all per-partition-set settings:
control column, partition interval/type, retention policy, template table, privileges-inheritance flags,
and `maintenance_role` (used for Row Level Security multi-tenancy, see README). Almost every function takes
`p_parent_table` and looks up its config row as the first step.

**Core operations**, each with a `_time` and `_id` variant (time-based vs. serial/ID-based partitioning),
plus shared helpers:
- `create_parent` / `create_sub_parent` — set up a new partition set (or sub-partitioned set) from an
  existing/new table, insert its `part_config` row.
- `create_partition_time` / `create_partition_id` (called by `create_partition`) — create individual child
  tables.
- `run_maintenance` (and `run_maintenance_proc`) — the periodic driver: premakes upcoming children, applies
  retention. This is what the BGW calls on its interval, and what an external scheduler would call instead
  of running the BGW. As of 5.5.0, a failure in one partition set's maintenance no longer aborts maintenance
  for other partition sets — it's logged as a warning and that set's `part_config.last_run` is cleared.
- `partition_data_time` / `partition_data_id` (and their `_proc`/`partition_data_async` procedure forms) —
  move existing rows from a non-partitioned (or default) table into the correct child partitions in
  batches.
- `drop_partition_time` / `drop_partition_id` — retention enforcement; can detach-then-drop
  (`detach_before_drop` in `part_config`) when a child is still referenced by a foreign key elsewhere.
- `undo_partition` / `undo_partition_proc` — reverse of the above: migrate a partition set back to a single
  plain table.
- `apply_privileges` / `reapply_privileges`, `apply_constraints` / `drop_constraints`,
  `inherit_parent_properties` / `inherit_template_properties` / `inherit_replica_identity` — keep child
  tables in sync with the parent/template table's grants, constraints, and other properties as new children
  are created.
- `show_partitions` / `show_partition_info` / `show_partition_name` — introspection helpers.

**Background worker (`src/pg_partman_bgw.c`).** A C bgworker loaded via `shared_preload_libraries`. Reads
GUCs (`pg_partman_bgw.interval`, `.role`, `.dbname`, `.analyze`, `.jobmon`, `.maintenance_wait`) and, per
configured database, connects as `pg_partman_bgw.role` and calls `run_maintenance()` on its interval.
`pg_partman_bgw.role` intentionally has no safe default that resolves to a superuser — since 5.5.0 it
defaults to a nonexistent placeholder (`partman_maintainer`) rather than silently running as whatever role
started the cluster, so operators are forced to configure a properly-scoped, non-superuser role (see
README's SETUP/privileges sections and the CVEs noted in `CHANGELOG.md` around running as superuser).

**Security model.** pg_partman does not require a superuser to install or run. Multiple CVEs fixed in 5.5.0
(see top of `CHANGELOG.md`) were about SQL injection / privilege escalation through user-controlled inputs
(time encoder/decoder functions, template table inheritance, pg_jobmon integration) and about
retention-schema table-ownership takeover in multi-tenant setups — when touching any code path that builds
dynamic SQL from `part_config`/`part_config_sub` values or from user-supplied identifiers, treat those
inputs as untrusted and check `partman_safe_obj_name.sql` / existing quoting patterns in similar functions
rather than introducing new string concatenation. Row Level Security policies (via `maintenance_role`) are
an intentional mitigation for multi-tenant use, documented in `README.md`'s "Row Level Security" section.

## Repo layout notes

- `doc/pg_partman.md` — the full reference manual; `doc/pg_partman_howto.md` — usage walkthrough;
  `doc/migrate_to_partman.md` / `doc/migrate_to_declarative.md` — migration guides. Update these alongside
  behavior changes to functions/procedures they document.
- `bin/common/*.py` — standalone maintenance scripts (dump/restore partition definitions, vacuum
  maintenance, unique-constraint checks), not part of the extension proper.
- `CHANGELOG.md` (current) and `CHANGELOG-pre-5.0.0.txt` (archived) — check the current file for the
  in-progress/unreleased entry style before adding a new one.
