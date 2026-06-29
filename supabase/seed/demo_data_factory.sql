-- Demo data factory helpers.
-- Optional helper functions for disposable demo environments.

CREATE OR REPLACE FUNCTION public.demo_next_number(p_prefix text)
RETURNS text LANGUAGE sql AS $$
  SELECT p_prefix || '-' || to_char(now(), 'YYYYMMDD-HH24MISS') || '-' || substr(gen_random_uuid()::text, 1, 6);
$$;

-- Creates a simple production order for the seeded Demo Metal Fittings Factory.
-- Requires supabase/seed/production_loop_seed.sql to have been run first.
CREATE OR REPLACE FUNCTION public.demo_create_production_order(p_qty numeric DEFAULT 10)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid;
  v_item uuid;
  v_uom uuid;
  v_po uuid;
BEGIN
  SELECT id INTO v_company FROM public.companies WHERE name = 'Demo Metal Fittings Factory' LIMIT 1;
  IF v_company IS NULL THEN RAISE EXCEPTION 'Run production_loop_seed.sql first'; END IF;
  SELECT id, default_uom_id INTO v_item, v_uom FROM public.items WHERE company_id = v_company AND item_code = 'BRACKET-DEMO-001';

  INSERT INTO public.production_orders(company_id, order_number, item_id, planned_quantity, uom_id, status, created_by)
  VALUES(v_company, public.demo_next_number('DEMO-PO'), v_item, p_qty, v_uom, 'PLANNED', auth.uid())
  RETURNING id INTO v_po;

  RETURN v_po;
END;
$$;
