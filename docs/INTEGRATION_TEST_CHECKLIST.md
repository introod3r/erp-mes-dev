# ERP/MES Integration Test Checklist

Use this checklist before any pilot or production deployment.

## 1. Master data setup

- [ ] Company exists and user is ADMIN.
- [ ] UOMs exist: PCS, KG.
- [ ] Warehouses exist: RM, WIP/optional, FG, QC, SCRAP.
- [ ] Raw material exists and is lot-tracked if required.
- [ ] Finished good exists and is manufactured/sellable.
- [ ] Work center exists.
- [ ] Machine exists and belongs to work center.
- [ ] Active default BOM exists for finished good.
- [ ] BOM lines have correct UOM and scrap factor.
- [ ] Active default routing exists.
- [ ] Routing operations are ordered and linked to work center.
- [ ] Scrap/downtime reason codes are seeded.

## 2. Inventory receipt

- [ ] Lot-tracked raw material cannot be received without lot.
- [ ] Purchase receipt creates inventory transaction header.
- [ ] Purchase receipt creates transaction line.
- [ ] Stock balance increases in correct warehouse/lot.
- [ ] Transaction cannot be deleted.
- [ ] Generic reversal works if stock is still available.

## 3. Production order release

- [ ] Planned production order can be created.
- [ ] Release fails without active default BOM.
- [ ] Release fails if multiple active default BOMs exist.
- [ ] Release detects BOM cycles.
- [ ] Release creates material snapshot.
- [ ] Multi-level BOM returns only leaf requirements.
- [ ] Release creates operation snapshot.
- [ ] First operation becomes READY.

## 4. Availability and reservation

- [ ] Availability shows on-hand, available and shortage.
- [ ] Reserve-all reserves only available stock.
- [ ] Reserve-all supports partial shortage.
- [ ] Manual reserve by lot/warehouse reserves requested balance.
- [ ] Reservation increases stock reserved quantity.
- [ ] Reservation increases production material reserved quantity.
- [ ] Release reservation decreases stock reserved quantity.
- [ ] Released reservation cannot be consumed.

## 5. Material issue / consumption

- [ ] Consumption fails if material is not reserved.
- [ ] Consumption fails above remaining reserved quantity.
- [ ] Consumption creates PRODUCTION_ISSUE transaction.
- [ ] Consumption decreases on-hand and reserved stock.
- [ ] Consumption updates reservation consumed quantity/status.
- [ ] Consumption updates production material consumed/issued quantity.
- [ ] Consumption moves order to IN_PROGRESS.
- [ ] Consumption reversal restores stock and reservation.

## 6. MES execution

- [ ] READY operation can be started.
- [ ] Start creates START event.
- [ ] Pause creates PAUSE event.
- [ ] Stop creates STOP event and does not complete operation.
- [ ] Quantity report creates REPORT_QTY event.
- [ ] Scrap report requires valid scrap reason code.
- [ ] Complete marks operation COMPLETED.
- [ ] Completion makes next operation READY.
- [ ] Event reversal corrects reported quantities.

## 7. Finished goods receipt

- [ ] Receipt creates PRODUCTION_RECEIPT transaction.
- [ ] Receipt increases FG stock.
- [ ] Scrap receipt increases SCRAP stock.
- [ ] Receipt updates produced/scrap quantities on order.
- [ ] Receipt can finish order.
- [ ] Receipt reversal fails if stock has been used/reserved.
- [ ] Receipt reversal decreases produced/scrap quantities.

## 8. Quality hold / NCR

- [ ] NCR can be created.
- [ ] Quality hold requires available stock.
- [ ] Quality hold requires QUALITY warehouse.
- [ ] Quality hold moves stock to QC warehouse.
- [ ] Hold release moves stock back to source/target warehouse.
- [ ] Hold scrap moves stock to SCRAP warehouse.
- [ ] Linked NCR disposition updates on scrap.

## 9. Security / RLS

- [ ] User cannot see other company data.
- [ ] READ_ONLY cannot insert/update business records.
- [ ] OPERATOR cannot change BOM/routing.
- [ ] WAREHOUSE cannot change BOM/routing.
- [ ] QUALITY cannot perform unauthorized production planning actions.
- [ ] Critical stock changes are only possible via RPC/API workflow.

## 10. Concurrency

- [ ] Two sessions cannot reserve same available stock twice.
- [ ] Two sessions cannot consume same reservation twice.
- [ ] Receipt reversal cannot race with stock reservation/shipment.
- [ ] Stock balances never become negative.
- [ ] Reserved quantity never exceeds on-hand.
