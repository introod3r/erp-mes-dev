# Production Pilot Checklist

This checklist is for a controlled factory pilot. It is not a go-live certification.

## 1. Environment readiness

- [ ] Supabase project created for pilot, separate from development.
- [ ] Database migrations applied in order.
- [ ] Backups enabled and restore process tested.
- [ ] Environment variables configured securely.
- [ ] CI build passes.
- [ ] Local Supabase SQL smoke tests pass.
- [ ] RLS negative tests pass.
- [ ] Error logging/monitoring configured.
- [ ] Admin user and company membership verified.

## 2. User and role readiness

- [ ] Users created for ADMIN, PLANNER, WAREHOUSE, PRODUCTION_OPERATOR, QUALITY, MANAGER, READ_ONLY.
- [ ] Each role tested with expected permissions.
- [ ] Operators cannot edit BOM/routing/items.
- [ ] Warehouse cannot edit BOM/routing.
- [ ] READ_ONLY cannot create/update records.
- [ ] Correction approvals limited to ADMIN/MANAGER.

## 3. Master data readiness

- [ ] UOMs validated.
- [ ] Warehouses and quality/scrap warehouses configured.
- [ ] Items loaded and classified correctly.
- [ ] Lot tracking enabled where required.
- [ ] BOMs validated by engineering/production.
- [ ] Routings validated by production.
- [ ] Work centers and machines configured.
- [ ] Scrap/downtime reason codes configured.
- [ ] Inspection plans configured for pilot items.

## 4. Inventory readiness

- [ ] Opening stock imported or manually posted.
- [ ] Lots verified physically and in system.
- [ ] Stock balance report reconciled with warehouse count.
- [ ] Quality hold warehouse empty/known at pilot start.
- [ ] SCRAP warehouse known at pilot start.
- [ ] Inventory reversal tested on test transaction.

## 5. Production process readiness

- [ ] Pilot production item selected.
- [ ] BOM release test passed.
- [ ] Production order release test passed.
- [ ] Material availability/shortage reviewed.
- [ ] Manual lot/warehouse reservation tested.
- [ ] Material consumption tested.
- [ ] Backflush tested only if BOM accuracy is approved.
- [ ] Finished goods receipt tested.
- [ ] Receipt reversal tested.

## 6. MES readiness

- [ ] Operator queue tested on shop-floor device.
- [ ] Barcode/order search tested.
- [ ] Start/pause/stop tested.
- [ ] Good quantity reporting tested.
- [ ] Scrap quantity reporting with reason code tested.
- [ ] Operation event history reviewed.
- [ ] Operation event correction request tested.

## 7. Quality readiness

- [ ] NCR creation tested.
- [ ] Quality hold from available stock tested.
- [ ] Quality hold release tested.
- [ ] Quality hold scrap tested.
- [ ] Inspection plan created.
- [ ] Inspection result pass/fail tested.
- [ ] Failed inspection escalation process agreed manually, if not automated.

## 8. Correction workflow readiness

- [ ] Correction request created for consumption reversal.
- [ ] Correction request approved.
- [ ] Correction request executed.
- [ ] Correction audit trail reviewed.
- [ ] Direct reversal policy agreed for emergency cases, if allowed.

## 9. Pilot execution rules

- [ ] Pilot limited to selected work center/item/shift.
- [ ] Manual paper backup process defined.
- [ ] Daily stock reconciliation during pilot.
- [ ] Daily production quantity reconciliation.
- [ ] Daily issue log reviewed.
- [ ] One responsible superuser assigned per shift.

## 10. Exit criteria

Pilot can expand only if:

- [ ] No unexplained negative stock.
- [ ] No reserved quantity greater than on-hand.
- [ ] Production order quantities reconcile.
- [ ] Inventory ledger reconciles with stock balances.
- [ ] Operators can complete workflow without developer assistance.
- [ ] Corrections are traceable and approved.
- [ ] Management accepts pilot reports.
