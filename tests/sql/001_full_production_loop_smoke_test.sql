-- Full ERP/MES-lite production-loop smoke test.
-- Run after all migrations. Recommended on a disposable Supabase project.
-- It uses a synthetic auth user and JWT claim to exercise SECURITY DEFINER RPCs.

BEGIN;

DO $$
DECLARE
  v_user uuid := '00000000-0000-0000-0000-000000000201'::uuid;
  v_company uuid;
  v_pcs uuid;
  v_kg uuid;
  v_rm uuid;
  v_fg uuid;
  v_qc uuid;
  v_scrap uuid;
  v_steel uuid;
  v_bracket uuid;
  v_lot uuid;
  v_wc uuid;
  v_bom uuid;
  v_routing uuid;
  v_po uuid;
  v_pom uuid;
  v_op uuid;
  v_tx uuid;
  v_receipt_tx uuid;
  v_consumption uuid;
  v_receipt uuid;
  v_hold uuid;
  v_ncr uuid;
  v_count int;
  v_num numeric;
BEGIN
  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);

  INSERT INTO auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES(v_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'smoke-test@example.com', '', now(), now(), now())
  ON CONFLICT(id) DO NOTHING;

  INSERT INTO public.companies(name) VALUES('Smoke Test Factory') RETURNING id INTO v_company;
  INSERT INTO public.company_memberships(company_id, user_id, role) VALUES(v_company, v_user, 'ADMIN');

  PERFORM public.seed_basic_master_data(v_company);
  PERFORM public.seed_reason_codes(v_company);

  SELECT id INTO v_pcs FROM public.units_of_measure WHERE company_id = v_company AND code = 'PCS';
  SELECT id INTO v_kg FROM public.units_of_measure WHERE company_id = v_company AND code = 'KG';
  SELECT id INTO v_rm FROM public.warehouses WHERE company_id = v_company AND code = 'RM';
  SELECT id INTO v_fg FROM public.warehouses WHERE company_id = v_company AND code = 'FG';
  SELECT id INTO v_qc FROM public.warehouses WHERE company_id = v_company AND code = 'QC';
  SELECT id INTO v_scrap FROM public.warehouses WHERE company_id = v_company AND code = 'SCRAP';
  SELECT id INTO v_steel FROM public.items WHERE company_id = v_company AND item_code = 'STEEL-STRIP-001';
  SELECT id INTO v_bracket FROM public.items WHERE company_id = v_company AND item_code = 'BRACKET-001';

  INSERT INTO public.lots(company_id, item_id, lot_number) VALUES(v_company, v_steel, 'SMOKE-STEEL-LOT-001') RETURNING id INTO v_lot;

  v_tx := public.post_inventory_transaction(v_company, 'PURCHASE_RECEIPT', NULL, NULL, 'SMOKE-GRN-001', 'Smoke test receipt', jsonb_build_array(jsonb_build_object(
    'item_id', v_steel, 'lot_id', v_lot, 'to_warehouse_id', v_rm, 'quantity', 100, 'uom_id', v_kg
  )));

  SELECT quantity_on_hand INTO v_num FROM public.stock_balances WHERE company_id = v_company AND item_id = v_steel AND warehouse_id = v_rm AND lot_id = v_lot;
  IF v_num <> 100 THEN RAISE EXCEPTION 'Expected steel stock 100, got %', v_num; END IF;

  INSERT INTO public.work_centers(company_id, code, name) VALUES(v_company, 'STAMP', 'Stamping') RETURNING id INTO v_wc;
  INSERT INTO public.boms(company_id, parent_item_id, bom_code, version, status, valid_from, output_quantity, output_uom_id, is_default)
  VALUES(v_company, v_bracket, 'SMOKE-BRACKET-BOM', '1', 'ACTIVE', CURRENT_DATE, 1, v_pcs, true) RETURNING id INTO v_bom;
  INSERT INTO public.bom_lines(company_id, bom_id, component_item_id, quantity_per, uom_id, scrap_factor_percent, issue_method, operation_sequence)
  VALUES(v_company, v_bom, v_steel, 0.1, v_kg, 0, 'MANUAL', 10);

  INSERT INTO public.routings(company_id, item_id, routing_code, version, status, valid_from, is_default)
  VALUES(v_company, v_bracket, 'SMOKE-BRACKET-RTG', '1', 'ACTIVE', CURRENT_DATE, true) RETURNING id INTO v_routing;
  INSERT INTO public.routing_operations(company_id, routing_id, sequence_no, operation_code, operation_name, work_center_id)
  VALUES(v_company, v_routing, 10, 'STAMP', 'Stamping', v_wc);

  INSERT INTO public.production_orders(company_id, order_number, item_id, planned_quantity, uom_id, status, created_by)
  VALUES(v_company, 'SMOKE-PO-001', v_bracket, 10, v_pcs, 'PLANNED', v_user) RETURNING id INTO v_po;

  PERFORM public.release_production_order(v_po);
  SELECT count(*) INTO v_count FROM public.production_order_materials WHERE production_order_id = v_po;
  IF v_count <> 1 THEN RAISE EXCEPTION 'Expected 1 material snapshot, got %', v_count; END IF;
  SELECT id INTO v_pom FROM public.production_order_materials WHERE production_order_id = v_po;
  SELECT id INTO v_op FROM public.production_order_operations WHERE production_order_id = v_po;

  PERFORM public.reserve_production_order_materials(v_po, v_rm);
  SELECT reserved_qty INTO v_num FROM public.production_order_materials WHERE id = v_pom;
  IF v_num <> 1 THEN RAISE EXCEPTION 'Expected reserved material 1kg, got %', v_num; END IF;

  PERFORM public.consume_production_material(v_pom, 1);
  SELECT consumed_qty INTO v_num FROM public.production_order_materials WHERE id = v_pom;
  IF v_num <> 1 THEN RAISE EXCEPTION 'Expected consumed material 1kg, got %', v_num; END IF;

  PERFORM public.start_production_operation(v_op, NULL);
  PERFORM public.report_production_operation(v_op, 10, 0, NULL, 'smoke report', true);
  SELECT status INTO STRICT v_num FROM (SELECT CASE WHEN status='COMPLETED' THEN 1 ELSE 0 END AS status FROM public.production_order_operations WHERE id = v_op) s;
  IF v_num <> 1 THEN RAISE EXCEPTION 'Operation was not completed'; END IF;

  v_receipt_tx := public.receive_finished_goods(v_po, v_fg, 10, 0, NULL, NULL, true);
  SELECT produced_quantity INTO v_num FROM public.production_orders WHERE id = v_po;
  IF v_num <> 10 THEN RAISE EXCEPTION 'Expected produced 10, got %', v_num; END IF;

  SELECT id INTO v_receipt FROM public.production_receipts WHERE production_order_id = v_po LIMIT 1;
  PERFORM public.reverse_production_receipt(v_receipt, 'smoke reversal');
  SELECT produced_quantity INTO v_num FROM public.production_orders WHERE id = v_po;
  IF v_num <> 0 THEN RAISE EXCEPTION 'Expected produced 0 after reversal, got %', v_num; END IF;

  v_ncr := public.create_nonconformance_report(v_company, 'SMOKE-NCR-001', 'Smoke NCR', v_steel, v_lot, 'TEST', v_po, 'LOW');
  v_hold := public.create_quality_hold(v_company, 'SMOKE-QH-001', v_steel, v_rm, v_qc, 1, v_lot, NULL, NULL, v_ncr, 'TEST', 'Smoke hold');
  PERFORM public.release_quality_hold(v_hold, NULL, NULL, NULL, 'Smoke release');

  RAISE NOTICE 'SMOKE TEST PASSED company_id=% po_id=%', v_company, v_po;
END $$;

ROLLBACK;
