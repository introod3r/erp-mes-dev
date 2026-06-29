-- Onboarding helpers for authenticated Supabase users.
-- Apply after 001_core_erp_mes_schema.sql

CREATE OR REPLACE FUNCTION public.create_company_with_admin(p_company_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
  END IF;

  IF trim(COALESCE(p_company_name, '')) = '' THEN
    RAISE EXCEPTION 'Company name is required';
  END IF;

  INSERT INTO public.companies(name)
  VALUES(trim(p_company_name))
  RETURNING id INTO v_company_id;

  INSERT INTO public.company_memberships(company_id, user_id, role, is_active)
  VALUES(v_company_id, auth.uid(), 'ADMIN', true);

  RETURN v_company_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.seed_basic_master_data(p_company_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pcs uuid;
  v_kg uuid;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['ADMIN']) THEN
    RAISE EXCEPTION 'Only company admin can seed master data' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.units_of_measure(company_id, code, name, symbol)
  VALUES
    (p_company_id, 'PCS', 'Pieces', 'pcs'),
    (p_company_id, 'KG', 'Kilogram', 'kg'),
    (p_company_id, 'M', 'Meter', 'm')
  ON CONFLICT(company_id, code) DO NOTHING;

  SELECT id INTO v_pcs FROM public.units_of_measure WHERE company_id = p_company_id AND code = 'PCS';
  SELECT id INTO v_kg FROM public.units_of_measure WHERE company_id = p_company_id AND code = 'KG';

  INSERT INTO public.warehouses(company_id, code, name, warehouse_type)
  VALUES
    (p_company_id, 'RM', 'Raw Material Warehouse', 'RAW_MATERIAL'),
    (p_company_id, 'WIP', 'Work In Progress', 'WIP'),
    (p_company_id, 'FG', 'Finished Goods Warehouse', 'FINISHED_GOODS'),
    (p_company_id, 'SCRAP', 'Scrap Warehouse', 'SCRAP'),
    (p_company_id, 'QC', 'Quality Hold', 'QUALITY')
  ON CONFLICT(company_id, code) DO NOTHING;

  IF v_kg IS NOT NULL THEN
    INSERT INTO public.items(company_id, item_code, item_type, default_uom_id, name, is_stocked, is_purchased, is_lot_tracked)
    VALUES(p_company_id, 'STEEL-STRIP-001', 'RAW_MATERIAL', v_kg, 'Steel strip sample', true, true, true)
    ON CONFLICT(company_id, item_code) DO NOTHING;
  END IF;

  IF v_pcs IS NOT NULL THEN
    INSERT INTO public.items(company_id, item_code, item_type, default_uom_id, name, is_stocked, is_manufactured, is_sellable)
    VALUES(p_company_id, 'BRACKET-001', 'FINISHED_GOOD', v_pcs, 'Mounting bracket sample', true, true, true)
    ON CONFLICT(company_id, item_code) DO NOTHING;
  END IF;
END;
$$;
