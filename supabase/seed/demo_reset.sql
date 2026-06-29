-- Demo data reset script.
-- Deletes the demo company created by production_loop_seed.sql and related rows.
-- Run only in local/demo environments.

DO $$
DECLARE
  v_company uuid;
BEGIN
  SELECT id INTO v_company FROM public.companies WHERE name = 'Demo Metal Fittings Factory' LIMIT 1;
  IF v_company IS NULL THEN
    RAISE NOTICE 'Demo company not found. Nothing to reset.';
    RETURN;
  END IF;

  DELETE FROM public.inspection_results WHERE company_id = v_company;
  DELETE FROM public.quality_inspections WHERE company_id = v_company;
  DELETE FROM public.inspection_characteristics WHERE company_id = v_company;
  DELETE FROM public.inspection_plans WHERE company_id = v_company;
  DELETE FROM public.correction_requests WHERE company_id = v_company;
  DELETE FROM public.quality_holds WHERE company_id = v_company;
  DELETE FROM public.nonconformance_reports WHERE company_id = v_company;
  DELETE FROM public.production_operation_events WHERE company_id = v_company;
  DELETE FROM public.production_receipts WHERE company_id = v_company;
  DELETE FROM public.production_consumptions WHERE company_id = v_company;
  DELETE FROM public.inventory_reservations WHERE company_id = v_company;
  DELETE FROM public.production_order_operations WHERE company_id = v_company;
  DELETE FROM public.production_order_materials WHERE company_id = v_company;
  DELETE FROM public.production_orders WHERE company_id = v_company;
  DELETE FROM public.inventory_transaction_lines WHERE company_id = v_company;
  DELETE FROM public.inventory_transactions WHERE company_id = v_company;
  DELETE FROM public.stock_balances WHERE company_id = v_company;
  DELETE FROM public.routing_operations WHERE company_id = v_company;
  DELETE FROM public.routings WHERE company_id = v_company;
  DELETE FROM public.bom_lines WHERE company_id = v_company;
  DELETE FROM public.boms WHERE company_id = v_company;
  DELETE FROM public.machines WHERE company_id = v_company;
  DELETE FROM public.work_centers WHERE company_id = v_company;
  DELETE FROM public.lots WHERE company_id = v_company;
  DELETE FROM public.item_translations WHERE item_id IN (SELECT id FROM public.items WHERE company_id = v_company);
  DELETE FROM public.unit_conversions WHERE company_id = v_company;
  DELETE FROM public.items WHERE company_id = v_company;
  DELETE FROM public.warehouse_locations WHERE company_id = v_company;
  DELETE FROM public.warehouses WHERE company_id = v_company;
  DELETE FROM public.units_of_measure WHERE company_id = v_company;
  DELETE FROM public.scrap_reason_codes WHERE company_id = v_company;
  DELETE FROM public.downtime_reason_codes WHERE company_id = v_company;
  DELETE FROM public.audit_log WHERE company_id = v_company;
  DELETE FROM public.company_memberships WHERE company_id = v_company;
  DELETE FROM public.companies WHERE id = v_company;

  RAISE NOTICE 'Demo company reset complete: %', v_company;
END $$;
