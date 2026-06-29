# Supabase Cloud Setup

Project URL:

```text
https://scotfeviezjiqckwwnxn.supabase.co
```

Project ref:

```text
scotfeviezjiqckwwnxn
```

## 1. Required values

From Supabase Dashboard → Project Settings → API:

```text
Project URL
anon public key
service_role key, server-side only
```

From Supabase Dashboard → Project Settings → Database:

```text
Database host
Database password
Connection string
```

Do not commit database passwords, service role keys, JWT secrets, or `.env.local`.

## 2. Local environment

Create `.env.local`:

```bash
cp .env.example .env.local
```

Set:

```env
NEXT_PUBLIC_SUPABASE_URL=https://scotfeviezjiqckwwnxn.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key_here
```

For server-only scripts, set the database URL in your shell, not in a committed file:

```bash
export SUPABASE_DB_URL='postgresql://postgres:<PASSWORD>@db.scotfeviezjiqckwwnxn.supabase.co:5432/postgres?sslmode=require'
```

If your Supabase project uses the transaction pooler, use the connection string supplied by Supabase Dashboard instead.

## 3. Apply migrations

Option A — Supabase CLI:

```bash
supabase login
supabase link --project-ref scotfeviezjiqckwwnxn
supabase db push
```

Option B — direct `psql`:

```bash
export SUPABASE_DB_URL='postgresql://postgres:<PASSWORD>@db.scotfeviezjiqckwwnxn.supabase.co:5432/postgres?sslmode=require'
npm run db:push:remote
```

The script applies all SQL files in:

```text
supabase/migrations/
```

in sorted order.

## 4. Run remote smoke tests

Use only on development/staging Supabase projects.

```bash
export SUPABASE_DB_URL='postgresql://postgres:<PASSWORD>@db.scotfeviezjiqckwwnxn.supabase.co:5432/postgres?sslmode=require'
npm run test:remote
```

This runs:

```text
tests/sql/001_full_production_loop_smoke_test.sql
tests/sql/003_rls_negative_role_tests.sql
```

## 5. Seed demo data

After migrations:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/production_loop_seed.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/demo_data_factory.sql
```

To remove demo data:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/demo_reset.sql
```

## 6. Security note

The database password was shared during setup. After migrations and CI/deployment setup are complete, rotate it in Supabase Dashboard and update your local/CI secrets.
