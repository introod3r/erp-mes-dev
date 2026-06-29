#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo "SUPABASE_DB_URL is required." >&2
  echo "Example: SUPABASE_DB_URL='postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres?sslmode=require' ./scripts/run-remote-supabase-tests.sh" >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required." >&2
  exit 1
fi

# These tests run in transactions with ROLLBACK where possible.
# Use a staging/dev Supabase project, never production, unless you have reviewed the tests.
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f tests/sql/001_full_production_loop_smoke_test.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f tests/sql/003_rls_negative_role_tests.sql

echo "Remote Supabase SQL tests passed."
