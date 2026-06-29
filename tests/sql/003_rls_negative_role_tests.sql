-- RLS negative role tests.
-- Run on a disposable/local Supabase database after all migrations.
-- This test switches to role authenticated so RLS policies are actually enforced.

BEGIN;

DO $$
DECLARE
  v_company uuid;
  v_admin uuid := '00000000-0000-0000-0000-000000000301'::uuid;
  v_readonly uuid := '00000000-0000-0000-0000-000000000302'::uuid;
  v_operator uuid := '00000000-0000-0000-0000-000000000303'::uuid;
  v_warehouse uuid := '00000000-0000-0000-0000-000000000304'::uuid;
  v_pcs uuid;
  v_item uuid;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_admin, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-admin@example.com', '', now(), now(), now()),
    (v_readonly, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-readonly@example.com', '', now(), now(), now()),
    (v_operator, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-operator@example.com', '', now(), now(), now()),
    (v_warehouse, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-warehouse@example.com', '', now(), now(), now())
  ON CONFLICT(id) DO NOTHING;

  INSERT INTO public.companies(name) VALUES('RLS Negative Test Factory') RETURNING id INTO v_company;
  INSERT INTO public.company_memberships(company_id, user_id, role) VALUES
    (v_company, v_admin, 'ADMIN'),
    (v_company, v_readonly, 'READ_ONLY'),
    (v_company, v_operator, 'PRODUCTION_OPERATOR'),
    (v_company, v_warehouse, 'WAREHOUSE');

  INSERT INTO public.units_of_measure(company_id, code, name, symbol) VALUES(v_company, 'PCS', 'Pieces', 'pcs') RETURNING id INTO v_pcs;
  INSERT INTO public.items(company_id, item_code, item_type, default_uom_id, name) VALUES(v_company, 'RLS-ITEM-001', 'RAW_MATERIAL', v_pcs, 'RLS item') RETURNING id INTO v_item;
  INSERT INTO public.warehouses(company_id, code, name, warehouse_type) VALUES(v_company, 'RLS-WH', 'RLS warehouse', 'RAW_MATERIAL');
END $$;

SET LOCAL ROLE authenticated;

DO $$
DECLARE
  v_company uuid;
  v_readonly uuid := '00000000-0000-0000-0000-000000000302'::uuid;
  v_operator uuid := '00000000-0000-0000-0000-000000000303'::uuid;
  v_warehouse uuid := '00000000-0000-0000-0000-000000000304'::uuid;
  v_pcs uuid;
  v_item uuid;
  v_wh uuid;
  v_failed boolean;
BEGIN
  -- READ_ONLY must not create item.
  PERFORM set_config('request.jwt.claim.sub', v_readonly::text, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
  SELECT id INTO v_company FROM public.companies WHERE name = 'RLS Negative Test Factory';
  SELECT id INTO v_pcs FROM public.units_of_measure WHERE company_id = v_company AND code = 'PCS';
  v_failed := false;
  BEGIN
    INSERT INTO public.items(company_id, item_code, item_type, default_uom_id, name)
    VALUES(v_company, 'RLS-SHOULD-FAIL-READONLY', 'RAW_MATERIAL', v_pcs, 'Should fail');
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'RLS failure: READ_ONLY inserted item'; END IF;

  -- PRODUCTION_OPERATOR must not create BOM.
  PERFORM set_config('request.jwt.claim.sub', v_operator::text, true);
  SELECT id INTO v_company FROM public.companies WHERE name = 'RLS Negative Test Factory';
  SELECT id INTO v_pcs FROM public.units_of_measure WHERE company_id = v_company AND code = 'PCS';
  SELECT id INTO v_item FROM public.items WHERE company_id = v_company AND item_code = 'RLS-ITEM-001';
  v_failed := false;
  BEGIN
    INSERT INTO public.boms(company_id, parent_item_id, bom_code, version, status, valid_from, output_quantity, output_uom_id, is_default)
    VALUES(v_company, v_item, 'RLS-SHOULD-FAIL-BOM', '1', 'ACTIVE', CURRENT_DATE, 1, v_pcs, true);
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'RLS failure: PRODUCTION_OPERATOR inserted BOM'; END IF;

  -- WAREHOUSE must not create routing.
  PERFORM set_config('request.jwt.claim.sub', v_warehouse::text, true);
  SELECT id INTO v_company FROM public.companies WHERE name = 'RLS Negative Test Factory';
  SELECT id INTO v_item FROM public.items WHERE company_id = v_company AND item_code = 'RLS-ITEM-001';
  v_failed := false;
  BEGIN
    INSERT INTO public.routings(company_id, item_id, routing_code, version, status, valid_from, is_default)
    VALUES(v_company, v_item, 'RLS-SHOULD-FAIL-RTG', '1', 'ACTIVE', CURRENT_DATE, true);
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'RLS failure: WAREHOUSE inserted routing'; END IF;

  -- Direct stock balance mutation must fail for WAREHOUSE after critical-table hardening.
  SELECT id INTO v_wh FROM public.warehouses WHERE company_id = v_company AND code = 'RLS-WH';
  v_failed := false;
  BEGIN
    INSERT INTO public.stock_balances(company_id, item_id, warehouse_id, quantity_on_hand)
    VALUES(v_company, v_item, v_wh, 999);
  EXCEPTION WHEN OTHERS THEN
    v_failed := true;
  END;
  IF NOT v_failed THEN RAISE EXCEPTION 'RLS failure: WAREHOUSE directly inserted stock balance'; END IF;

  RAISE NOTICE 'RLS NEGATIVE TESTS PASSED company_id=%', v_company;
END $$;

ROLLBACK;
