-- Demo seed scenario for complete ERP/MES-lite production loop.
-- Purpose: creates a realistic demo company master-data set.
-- Run in Supabase SQL editor or via psql with a service/admin connection.
-- This script is idempotent for codes/numbers used below.

DO $$
DECLARE
  v_company uuid;
  v_user uuid := '00000000-0000-0000-0000-000000000101'::uuid;
  v_pcs uuid;
  v_kg uuid;
  v_rm uuid;
  v_fg uuid;
  v_qc uuid;
  v_scrap uuid;
  v_steel uuid;
  v_bracket uuid;
  v_lot uuid;
  v_bom uuid;
  v_wc uuid;
  v_machine uuid;
  v_routing uuid;
BEGIN
  -- Demo auth user for SQL/RPC testing. Safe to skip if auth.users insert is restricted in your environment.
  INSERT INTO auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES(v_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'demo-operator@example.com', '', now(), now(), now())
  ON CONFLICT(id) DO NOTHING;

  INSERT INTO public.companies(name)
  VALUES('Demo Metal Fittings Factory')
  ON CONFLICT DO NOTHING;

  SELECT id INTO v_company FROM public.companies WHERE name = 'Demo Metal Fittings Factory' LIMIT 1;

  INSERT INTO public.company_memberships(company_id, user_id, role)
  VALUES(v_company, v_user, 'ADMIN')
  ON CONFLICT(company_id, user_id) DO UPDATE SET role = 'ADMIN', is_active = true;

  INSERT INTO public.units_of_measure(company_id, code, name, symbol)
  VALUES
    (v_company, 'PCS', 'Pieces', 'pcs'),
    (v_company, 'KG', 'Kilogram', 'kg')
  ON CONFLICT(company_id, code) DO NOTHING;
  SELECT id INTO v_pcs FROM public.units_of_measure WHERE company_id = v_company AND code = 'PCS';
  SELECT id INTO v_kg FROM public.units_of_measure WHERE company_id = v_company AND code = 'KG';

  INSERT INTO public.warehouses(company_id, code, name, warehouse_type)
  VALUES
    (v_company, 'RM', 'Raw Material Warehouse', 'RAW_MATERIAL'),
    (v_company, 'FG', 'Finished Goods Warehouse', 'FINISHED_GOODS'),
    (v_company, 'QC', 'Quality Hold', 'QUALITY'),
    (v_company, 'SCRAP', 'Scrap Warehouse', 'SCRAP')
  ON CONFLICT(company_id, code) DO NOTHING;
  SELECT id INTO v_rm FROM public.warehouses WHERE company_id = v_company AND code = 'RM';
  SELECT id INTO v_fg FROM public.warehouses WHERE company_id = v_company AND code = 'FG';
  SELECT id INTO v_qc FROM public.warehouses WHERE company_id = v_company AND code = 'QC';
  SELECT id INTO v_scrap FROM public.warehouses WHERE company_id = v_company AND code = 'SCRAP';

  INSERT INTO public.items(company_id, item_code, item_type, default_uom_id, name, is_stocked, is_purchased, is_lot_tracked)
  VALUES(v_company, 'STEEL-STRIP-DC01', 'RAW_MATERIAL', v_kg, 'Steel strip DC01 1.5mm', true, true, true)
  ON CONFLICT(company_id, item_code) DO UPDATE SET name = EXCLUDED.name;
  SELECT id INTO v_steel FROM public.items WHERE company_id = v_company AND item_code = 'STEEL-STRIP-DC01';

  INSERT INTO public.items(company_id, item_code, item_type, default_uom_id, name, is_stocked, is_manufactured, is_sellable)
  VALUES(v_company, 'BRACKET-DEMO-001', 'FINISHED_GOOD', v_pcs, 'Demo mounting bracket', true, true, true)
  ON CONFLICT(company_id, item_code) DO UPDATE SET name = EXCLUDED.name;
  SELECT id INTO v_bracket FROM public.items WHERE company_id = v_company AND item_code = 'BRACKET-DEMO-001';

  INSERT INTO public.lots(company_id, item_id, lot_number, supplier_lot_number)
  VALUES(v_company, v_steel, 'STEEL-LOT-DEMO-001', 'SUP-LOT-001')
  ON CONFLICT(company_id, item_id, lot_number) DO NOTHING;
  SELECT id INTO v_lot FROM public.lots WHERE company_id = v_company AND item_id = v_steel AND lot_number = 'STEEL-LOT-DEMO-001';

  INSERT INTO public.work_centers(company_id, code, name, department)
  VALUES(v_company, 'STAMP', 'Stamping', 'Production')
  ON CONFLICT(company_id, code) DO NOTHING;
  SELECT id INTO v_wc FROM public.work_centers WHERE company_id = v_company AND code = 'STAMP';

  INSERT INTO public.machines(company_id, work_center_id, code, name, machine_type)
  VALUES(v_company, v_wc, 'PRESS-DEMO-01', 'Demo mechanical press 01', 'Press')
  ON CONFLICT(company_id, code) DO NOTHING;
  SELECT id INTO v_machine FROM public.machines WHERE company_id = v_company AND code = 'PRESS-DEMO-01';

  INSERT INTO public.boms(company_id, parent_item_id, bom_code, version, status, valid_from, output_quantity, output_uom_id, is_default)
  VALUES(v_company, v_bracket, 'BRACKET-DEMO-001-BOM', '1', 'ACTIVE', CURRENT_DATE, 1, v_pcs, true)
  ON CONFLICT(company_id, bom_code, version) DO UPDATE SET status = 'ACTIVE', is_default = true;
  SELECT id INTO v_bom FROM public.boms WHERE company_id = v_company AND bom_code = 'BRACKET-DEMO-001-BOM' AND version = '1';

  IF NOT EXISTS (SELECT 1 FROM public.bom_lines WHERE bom_id = v_bom AND component_item_id = v_steel) THEN
    INSERT INTO public.bom_lines(company_id, bom_id, component_item_id, quantity_per, uom_id, scrap_factor_percent, issue_method, operation_sequence)
    VALUES(v_company, v_bom, v_steel, 0.10, v_kg, 5, 'MANUAL', 10);
  END IF;

  INSERT INTO public.routings(company_id, item_id, routing_code, version, status, valid_from, is_default)
  VALUES(v_company, v_bracket, 'BRACKET-DEMO-001-RTG', '1', 'ACTIVE', CURRENT_DATE, true)
  ON CONFLICT(company_id, routing_code, version) DO UPDATE SET status = 'ACTIVE', is_default = true;
  SELECT id INTO v_routing FROM public.routings WHERE company_id = v_company AND routing_code = 'BRACKET-DEMO-001-RTG' AND version = '1';

  INSERT INTO public.routing_operations(company_id, routing_id, sequence_no, operation_code, operation_name, work_center_id, setup_time_minutes, run_time_minutes_per_unit)
  VALUES(v_company, v_routing, 10, 'STAMP', 'Stamp bracket blank', v_wc, 15, 0.03)
  ON CONFLICT(routing_id, sequence_no) DO UPDATE SET operation_name = EXCLUDED.operation_name;

  -- Stock seed is direct to ledger/balance to remain idempotent in demo data.
  IF NOT EXISTS (SELECT 1 FROM public.inventory_transactions WHERE company_id = v_company AND reference_number = 'DEMO-GRN-001') THEN
    INSERT INTO public.inventory_transactions(company_id, transaction_type, reference_number, note, created_by)
    VALUES(v_company, 'PURCHASE_RECEIPT', 'DEMO-GRN-001', 'Demo initial steel receipt', v_user);

    INSERT INTO public.inventory_transaction_lines(company_id, transaction_id, item_id, lot_id, to_warehouse_id, quantity, uom_id)
    SELECT v_company, it.id, v_steel, v_lot, v_rm, 100, v_kg
    FROM public.inventory_transactions it
    WHERE it.company_id = v_company AND it.reference_number = 'DEMO-GRN-001';

    INSERT INTO public.stock_balances(company_id, item_id, warehouse_id, lot_id, quantity_on_hand)
    VALUES(v_company, v_steel, v_rm, v_lot, 100)
    ON CONFLICT(company_id, item_id, warehouse_id, location_id, lot_id)
    DO UPDATE SET quantity_on_hand = public.stock_balances.quantity_on_hand + 100, updated_at = now();
  END IF;

  RAISE NOTICE 'Demo seed complete. company_id=%, demo_user_id=%', v_company, v_user;
END $$;
