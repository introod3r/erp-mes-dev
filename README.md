# Metal Fittings ERP/MES Starter

Production-management starter for a company manufacturing small metal furniture fittings.

This is **not a toy inventory table**. The foundation uses:

- Supabase/PostgreSQL schema with normalized master data
- Immutable inventory ledger + stock balance cache
- Lot-aware stock balances
- Material reservations
- Versioned BOM/routing structure
- Production orders, material snapshots, operation snapshots, and MES event logs
- Supabase Auth + company/role-based RLS foundation
- Next.js bilingual Serbian/English dashboard shell
- API routes for initial master/production data and safe inventory posting through RPC

## Project structure

```text
app/                         Next.js app router pages and API routes
app/api/items                Items API
app/api/warehouses           Warehouses API
app/api/production-orders    Production order API
app/api/inventory/post       Inventory posting API using DB RPC
components/                  Bilingual dashboard components
lib/                         Supabase clients and validation schemas
locales/                     English/Serbian translations
supabase/migrations/         PostgreSQL/Supabase migration
docs/                        Implementation notes
```

## Quick start

```bash
npm install
cp .env.example .env.local
npm run dev
```

Set these variables in `.env.local`:

```bash
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key
```

## Apply database migration

If using the Supabase CLI:

```bash
supabase link --project-ref your-project-ref
supabase db push
```

Main migration:

```text
supabase/migrations/001_core_erp_mes_schema.sql
supabase/migrations/002_onboarding_and_seed_helpers.sql
supabase/migrations/003_multilevel_bom_release.sql
supabase/migrations/004_material_availability_and_reservation.sql
supabase/migrations/005_consumption_and_receipts.sql
supabase/migrations/006_mes_operation_execution.sql
supabase/migrations/007_reason_codes_and_mes_history.sql
supabase/migrations/008_reservation_release.sql
supabase/migrations/009_controlled_reversals.sql
supabase/migrations/010_quality_hold_ncr.sql
supabase/migrations/011_rls_hardening_critical_tables.sql
supabase/migrations/012_correction_approval_workflow.sql
supabase/migrations/013_backflush_workflow.sql
supabase/migrations/014_inspection_module.sql
supabase/migrations/015_role_specific_rls_hardening.sql
```

## Test and pilot assets

```text
scripts/run-local-supabase-tests.sh
.github/workflows/ci.yml
supabase/config.toml
supabase/seed/production_loop_seed.sql
supabase/seed/demo_data_factory.sql
supabase/seed/demo_reset.sql
tests/sql/001_full_production_loop_smoke_test.sql
tests/sql/002_concurrency_manual_test.sql
tests/sql/003_rls_negative_role_tests.sql
docs/INTEGRATION_TEST_CHECKLIST.md
docs/PRODUCTION_PILOT_CHECKLIST.md
```

## Auth/RLS model

Every company-scoped table has `company_id`. Users are connected to companies through:

```sql
company_memberships(company_id, user_id, role)
```

Roles:

```text
ADMIN
PLANNER
WAREHOUSE
PRODUCTION_OPERATOR
QUALITY
MANAGER
READ_ONLY
```

RLS allows members to read company data and staff roles to insert/update. Critical inventory writes should go through PostgreSQL RPC functions.

## Critical RPC functions

### post_inventory_transaction

Creates immutable transaction header/lines and updates `stock_balances` inside the database transaction.

Example payload to `/api/inventory/post`:

```json
{
  "company_id": "...",
  "transaction_type": "PURCHASE_RECEIPT",
  "reference_number": "GRN-2026-0001",
  "lines": [
    {
      "item_id": "...",
      "to_warehouse_id": "...",
      "quantity": 1000,
      "uom_id": "...",
      "lot_id": "..."
    }
  ]
}
```

### release_production_order

Snapshots the currently active/default BOM and routing into a production order, then moves it from `PLANNED` to `RELEASED`. The implementation now uses recursive BOM explosion for leaf material requirements and includes basic cycle detection.

### reserve_production_material

Locks stock balance, checks available quantity, creates reservation, and increments reserved stock.

## UI pages included

```text
/                  Static bilingual landing shell
/login             Supabase sign-in/sign-up form
/onboarding        Create company tenant and first ADMIN membership
/dashboard         Company-aware operational dashboard
/items             Basic item master-data screen
/warehouses        Basic warehouse master-data screen
/inventory         Stock balance view and inventory-in posting
/resources         Work centers and machines screen
/bom-routing       Basic BOM and routing editor
/reason-codes      Scrap and downtime reason-code management
/quality           Quality holds and nonconformance reports
/operator          Shop-floor operator work queue
/production-orders Basic production order create/list/release screen
```

## API routes included

```text
GET/POST /api/uoms?company_id=...
GET/POST /api/items?company_id=...
GET/POST /api/warehouses?company_id=...
GET      /api/stock-balances?company_id=...
GET/POST /api/lots?company_id=...
GET/POST /api/work-centers?company_id=...
GET/POST /api/machines?company_id=...
GET/POST /api/boms?company_id=...
GET/POST /api/bom-lines?bom_id=...
GET/POST /api/routings?company_id=...
GET/POST /api/routing-operations?routing_id=...
GET/POST /api/scrap-reasons?company_id=...
GET/POST /api/downtime-reasons?company_id=...
POST     /api/reason-codes/seed
GET/POST /api/nonconformance-reports?company_id=...
GET/POST /api/quality-holds?company_id=...
POST     /api/quality-holds/:id/release
POST     /api/quality-holds/:id/scrap
GET      /api/operator-queue?company_id=...
GET/POST /api/production-orders?company_id=...
GET      /api/production-orders/:id/availability
POST     /api/production-orders/:id/reserve
POST     /api/production-order-materials/:id/reserve
POST     /api/production-order-materials/:id/consume
GET      /api/production-orders/:id/reservations
POST     /api/inventory-reservations/:id/release
POST     /api/production-orders/:id/release-reservations
GET      /api/production-orders/:id/consumptions
GET      /api/production-orders/:id/receipts
POST     /api/production-consumptions/:id/reverse
POST     /api/production-receipts/:id/reverse
POST     /api/operation-events/:id/reverse
POST     /api/inventory-transactions/:id/reverse
POST     /api/production-orders/:id/receive
POST     /api/production-order-operations/:id/start
POST     /api/production-order-operations/:id/pause
POST     /api/production-order-operations/:id/stop
POST     /api/production-order-operations/:id/report
POST     /api/production-orders/release
POST     /api/inventory/post
```

These are starter routes. In production you should add stricter workflow-specific endpoints, for example:

```text
POST /api/production-orders/:id/release
POST /api/production-orders/:id/reserve-materials
POST /api/production-orders/:id/consume
POST /api/production-orders/:id/receive-finished-goods
POST /api/operations/:id/start
POST /api/operations/:id/stop
```

## Serbian/English language support

Frontend labels use JSON locale files:

```text
locales/en.json
locales/sr.json
```

Business master data translations are supported through:

```sql
item_translations
```

Extend the same pattern for work centers, operations, scrap reasons, etc.

## Validation status

The generated Next.js project was checked with:

```bash
npm run typecheck
npm run build
```

Both completed successfully in this workspace.

## Important production warnings

Before going live, you still need to harden:

1. More restrictive role-specific RLS policies per table/action
2. Multi-level BOM explosion function
3. Full BOM/routing editor UI
4. Consumption and finished-goods receipt RPC functions
5. Reservation/picking UI and shortage handling
6. Reversal workflows for incorrect inventory postings
7. Full quality module
8. Costing/valuation model
9. Partitioning strategy for high-volume inventory ledger tables
10. Integration tests for inventory concurrency

The current foundation is intentionally strict about inventory traceability, but it is still a starter, not a complete ERP.
