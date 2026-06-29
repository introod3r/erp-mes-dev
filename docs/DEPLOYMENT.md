# Deployment Guide

Recommended deployment architecture:

```text
GitHub repo → CI checks → frontend hosting → Supabase Cloud
```

GitHub repository:

```text
https://github.com/introod3r/erp-mes-dev
```

Supabase project:

```text
https://scotfeviezjiqckwwnxn.supabase.co
```

## 1. Prepare GitHub repository

From the project root:

```bash
npm run git:setup-remote
```

Then:

```bash
git add .
git commit -m "Initial ERP/MES application"
git push -u origin main
```

If GitHub asks for credentials, use your GitHub account/token. Do not put tokens into project files.

## 2. GitHub Actions

CI workflow exists at:

```text
.github/workflows/ci.yml
```

Current checks:

```text
npm ci
npm run typecheck
npm run build
SQL asset presence check
```

Future improvement:

```text
Run Supabase local DB in CI and execute SQL smoke/RLS tests.
```

## 3. Frontend hosting

Recommended simple option:

```text
Vercel connected to GitHub
```

Required environment variables:

```env
NEXT_PUBLIC_SUPABASE_URL=https://scotfeviezjiqckwwnxn.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key_here
```

Do not expose:

```text
service_role key
database password
JWT secret
```

## 4. Database migration deployment

Preferred for first setup:

```bash
supabase login
supabase link --project-ref scotfeviezjiqckwwnxn
supabase db push
```

Alternative:

```bash
export SUPABASE_DB_URL='postgresql://postgres:<PASSWORD>@db.scotfeviezjiqckwwnxn.supabase.co:5432/postgres?sslmode=require'
npm run db:push:remote
```

## 5. Pilot data setup

Optional demo seed:

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/production_loop_seed.sql
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/seed/demo_data_factory.sql
```

## 6. Pre-pilot checks

Use:

```text
docs/PRODUCTION_PILOT_CHECKLIST.md
```

Minimum before pilot:

```text
migrations applied
build passes
smoke tests pass
RLS negative tests pass
roles verified
backup enabled
first pilot item/BOM/routing validated
opening stock reconciled
```
