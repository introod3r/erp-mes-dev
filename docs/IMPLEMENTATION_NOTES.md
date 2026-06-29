# Implementation Notes and Next Steps

## What has been built

A Next.js + Supabase starter for an ERP/MES-lite system.

### Database foundation

Migration file:

```text
supabase/migrations/001_core_erp_mes_schema.sql
```

Includes:

- Companies and company memberships
- Role model compatible with Supabase Auth
- Units of measure and unit conversions
- Items and item translations
- Warehouses and warehouse locations
- Lots/batches
- Versioned BOMs and BOM lines
- Work centers, machines, routings, routing operations
- Production orders
- Production order material snapshots
- Production order operation snapshots
- MES operation event log
- Immutable inventory transaction ledger
- Stock balance cache
- Inventory reservations
- Production consumption and receipt details
- Audit log
- RLS policies
- Inventory posting RPC
- Material reservation RPC

## Inventory model

The design intentionally separates:

```text
inventory_transactions / inventory_transaction_lines = historical truth
stock_balances = current-state cache
```

Never build production inventory using only a mutable `items.quantity` column.

## Current hard rules

The starter migration blocks direct deletes on ledger tables:

```text
inventory_transactions
inventory_transaction_lines
```

Incorrect inventory postings should be reversed, not deleted.

## Known limitations in this starter

### 1. UOM conversion in posting RPC

The `post_inventory_transaction` RPC currently requires transaction line UOM to equal the item's default UOM.

This is deliberate. Real UOM conversion must be added carefully because mistakes here corrupt inventory.

Recommended improvement:

- Add a `normalize_quantity_to_default_uom()` function
- Support item-specific conversions first
- Reject ambiguous conversions
- Store both entered quantity and normalized inventory quantity if needed

### 2. Company consistency constraints

Foreign keys do not fully enforce that all related records share the same `company_id`.

Recommended improvement:

- Add composite unique keys like `(company_id, id)`
- Use composite foreign keys from child tables
- Or add `validate_same_company()` triggers for critical tables

For a real ERP, this is important.

### 3. BOM explosion not yet implemented

The schema supports multi-level BOMs, but this starter does not yet include the recursive BOM explosion RPC.

Recommended function:

```text
explode_bom(parent_item_id, quantity, effective_date)
```

Then snapshot results into:

```text
production_order_materials
```

### 4. Production release workflow not yet implemented

A real release flow should:

1. Validate item is manufactured
2. Select active BOM/routing
3. Explode BOM
4. Snapshot BOM materials
5. Snapshot routing operations
6. Move status from PLANNED to RELEASED
7. Optionally reserve stock

This should be one transaction.

### 5. Consumption and receipt RPCs should be added

The generic inventory posting function is useful, but production should eventually use explicit workflow functions:

```text
consume_production_material()
receive_finished_goods()
backflush_materials_for_operation()
reverse_inventory_transaction()
```

### 6. RLS policies are intentionally broad for staff roles

The migration provides a working RLS foundation, not a final security model.

For production, restrict by role:

- WAREHOUSE: inventory operations
- PLANNER: production order creation/release
- PRODUCTION_OPERATOR: MES events and controlled reporting
- QUALITY: inspection, holds, releases
- ADMIN: master data/security
- READ_ONLY: select only

### 7. Partitioning not yet applied

At 10k+ production orders/month, inventory lines and MES event tables can grow quickly.

Consider monthly or quarterly partitioning for:

```text
inventory_transactions
inventory_transaction_lines
production_operation_events
audit_log
```

Do not add partitioning blindly; plan indexes and reporting first.

## Recommended next build steps

### Step 1: Onboarding/admin bootstrap

Create a secure bootstrap flow for first company/admin.

### Step 2: Master data screens

Add CRUD UI for:

- UOMs
- Items
- Warehouses/locations
- Work centers/machines
- BOMs
- Routings

### Step 3: Production order release RPC

This is the most important missing workflow after inventory posting.

### Step 4: Reservation and consumption screens

Implement warehouse operator flows:

- Reserve materials
- Pick materials
- Consume actual quantities
- Report shortages

### Step 5: MES operator screen

Simple shop-floor UI:

- Work queue by machine/work center
- Start/stop operation
- Report good quantity
- Report scrap quantity and reason

### Step 6: Quality module

Add at minimum:

```text
quality_inspections
inspection_characteristics
inspection_results
nonconformance_reports
quality_holds
scrap_reason_codes
```

### Step 7: Costing

Do not fake costing. Add it as a deliberate module after inventory flows are stable.
