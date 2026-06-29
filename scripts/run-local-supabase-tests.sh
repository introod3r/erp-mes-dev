#!/usr/bin/env bash
set -euo pipefail

if ! command -v supabase >/dev/null 2>&1; then
  echo "Supabase CLI is required: https://supabase.com/docs/guides/cli" >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required." >&2
  exit 1
fi

supabase start
supabase db reset --local

DB_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"

echo "Running production-loop smoke test..."
psql "$DB_URL" -v ON_ERROR_STOP=1 -f tests/sql/001_full_production_loop_smoke_test.sql

echo "Running RLS negative role tests..."
psql "$DB_URL" -v ON_ERROR_STOP=1 -f tests/sql/003_rls_negative_role_tests.sql

echo "Local Supabase SQL tests passed."
