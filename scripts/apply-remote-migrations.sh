#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo "SUPABASE_DB_URL is required." >&2
  echo "Example: SUPABASE_DB_URL='postgresql://postgres:<password>@db.<project-ref>.supabase.co:5432/postgres?sslmode=require' ./scripts/apply-remote-migrations.sh" >&2
  exit 1
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "psql is required." >&2
  exit 1
fi

for migration in $(find supabase/migrations -maxdepth 1 -type f -name '*.sql' | sort); do
  echo "Applying $migration"
  psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$migration"
done

echo "Remote migrations applied successfully."
