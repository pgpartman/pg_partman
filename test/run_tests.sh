#!/usr/bin/env bash
#
# Runs pg_partman tests inside Docker.
# Usage: ./test/run_tests.sh [--only-low-lock | --only-original | --all-top-level]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
SERVICE="pg"

PGUSER="partman_test"
PGDB="partman_test"
TEST_DIR="/pg_partman/test"

docker_psql() {
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" \
        psql -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 "$@"
}

docker_pg_prove() {
    docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" \
        pg_prove -U "$PGUSER" -d "$PGDB" -ovf "$@"
}

cleanup() {
    echo ""
    echo "=== Tearing down test environment ==="
    docker compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true
}
trap cleanup EXIT

start_db() {
    echo "=== Building and starting PostgreSQL container ==="
    docker compose -f "$COMPOSE_FILE" up -d --build --wait
    echo "=== Database ready ==="
}

run_procedure_test() {
    local test_name="$1"
    local part1="$2"
    local call_sql="$3"
    local part2="$4"
    local failed=0

    echo ""
    echo "========================================"
    echo "  TEST: $test_name"
    echo "========================================"

    echo "--- Part 1: Setup and populate ---"
    if ! docker_pg_prove "$part1"; then
        echo "--- FAILED part 1 ---"
        failed=1
    fi

    echo "--- Procedure call ---"
    if ! docker_psql -c "$call_sql"; then
        echo "--- FAILED procedure call ---"
        failed=1
    fi

    echo "--- Part 2: Verify and cleanup ---"
    if ! docker_pg_prove "$part2"; then
        echo "--- FAILED part 2 ---"
        failed=1
    fi

    if [ "$failed" -eq 0 ]; then
        echo "--- PASSED: $test_name ---"
    else
        echo "--- FAILED: $test_name ---"
        return 1
    fi
}

run_top_level_tests() {
    echo ""
    echo "========================================"
    echo "  TOP-LEVEL TESTS (single transaction)"
    echo "========================================"
    local failed=0
    local files
    files=$(docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" \
        find "$TEST_DIR" -maxdepth 1 -name 'test-*.sql' -type f | sort)
    for f in $files; do
        f=$(echo "$f" | tr -d '\r')
        echo ""
        echo "--- Running: $(basename "$f") ---"
        if docker_pg_prove "$f"; then
            echo "--- PASSED: $(basename "$f") ---"
        else
            echo "--- FAILED: $(basename "$f") ---"
            failed=$((failed + 1))
        fi
    done
    if [ "$failed" -gt 0 ]; then
        echo ""
        echo "!!! $failed top-level test(s) failed !!!"
        return 1
    fi
}

MODE="${1:-}"
FAILURES=0

start_db

if [ "$MODE" = "--only-original" ] || [ -z "$MODE" ]; then
    run_procedure_test \
        "reapply_constraints_proc (original weekly)" \
        "$TEST_DIR/test_procedure/test-time-procedure-weekly-part1.sql" \
        "CALL partman.reapply_constraints_proc('partman_test.time_taptest_table', p_drop_constraints := true, p_apply_constraints := true);" \
        "$TEST_DIR/test_procedure/test-time-procedure-weekly-part2.sql" \
    || FAILURES=$((FAILURES + 1))
fi

if [ "$MODE" = "--only-low-lock" ] || [ -z "$MODE" ]; then
    run_procedure_test \
        "reapply_constraints_proc (low-lock weekly)" \
        "$TEST_DIR/test_procedure/test-time-procedure-weekly-low-lock-part1.sql" \
        "CALL partman.reapply_constraints_proc('partman_test.time_taptest_table', p_drop_constraints := true, p_apply_constraints := true, p_low_lock := true);" \
        "$TEST_DIR/test_procedure/test-time-procedure-weekly-low-lock-part2.sql" \
    || FAILURES=$((FAILURES + 1))

    run_procedure_test \
        "reapply_constraints_proc (low-lock weekly, multi-column)" \
        "$TEST_DIR/test_procedure/test-time-procedure-weekly-low-lock-multicol-part1.sql" \
        "CALL partman.reapply_constraints_proc('partman_test.time_taptest_table', p_drop_constraints := true, p_apply_constraints := true, p_low_lock := true);" \
        "$TEST_DIR/test_procedure/test-time-procedure-weekly-low-lock-multicol-part2.sql" \
    || FAILURES=$((FAILURES + 1))
fi

if [ "$MODE" = "--all-top-level" ]; then
    run_top_level_tests || FAILURES=$((FAILURES + 1))
fi

echo ""
echo "========================================"
if [ "$FAILURES" -gt 0 ]; then
    echo "  RESULT: $FAILURES test suite(s) FAILED"
    echo "========================================"
    exit 1
else
    echo "  RESULT: All tests PASSED"
    echo "========================================"
    exit 0
fi
