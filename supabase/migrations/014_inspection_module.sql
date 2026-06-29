-- Inspection plans/results foundation.
-- Apply after 013_backflush_workflow.sql

CREATE TABLE IF NOT EXISTS public.inspection_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  plan_code text NOT NULL,
  name text NOT NULL,
  item_id uuid NULL REFERENCES public.items(id),
  inspection_type text NOT NULL CHECK (inspection_type IN ('INCOMING','IN_PROCESS','FINAL','AUDIT')),
  status text NOT NULL CHECK (status IN ('DRAFT','ACTIVE','OBSOLETE')) DEFAULT 'ACTIVE',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, plan_code)
);

CREATE TABLE IF NOT EXISTS public.inspection_characteristics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  inspection_plan_id uuid NOT NULL REFERENCES public.inspection_plans(id) ON DELETE CASCADE,
  sequence_no integer NOT NULL,
  characteristic_code text NOT NULL,
  name text NOT NULL,
  data_type text NOT NULL CHECK (data_type IN ('NUMERIC','BOOLEAN','TEXT')),
  nominal_value numeric(18,6),
  lower_limit numeric(18,6),
  upper_limit numeric(18,6),
  required boolean NOT NULL DEFAULT true,
  UNIQUE(inspection_plan_id, sequence_no)
);

CREATE TABLE IF NOT EXISTS public.quality_inspections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  inspection_number text NOT NULL,
  inspection_plan_id uuid NOT NULL REFERENCES public.inspection_plans(id),
  source_type text,
  source_id uuid,
  item_id uuid NULL REFERENCES public.items(id),
  lot_id uuid NULL REFERENCES public.lots(id),
  status text NOT NULL CHECK (status IN ('OPEN','PASSED','FAILED','CANCELLED')) DEFAULT 'OPEN',
  inspected_by uuid REFERENCES auth.users(id),
  inspected_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, inspection_number)
);

CREATE TABLE IF NOT EXISTS public.inspection_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  quality_inspection_id uuid NOT NULL REFERENCES public.quality_inspections(id) ON DELETE CASCADE,
  characteristic_id uuid NOT NULL REFERENCES public.inspection_characteristics(id),
  numeric_value numeric(18,6),
  boolean_value boolean,
  text_value text,
  passed boolean,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(quality_inspection_id, characteristic_id)
);

ALTER TABLE public.inspection_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_characteristics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quality_inspections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inspection_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY inspection_plans_member_select ON public.inspection_plans FOR SELECT USING (public.is_company_member(company_id));
CREATE POLICY inspection_characteristics_member_select ON public.inspection_characteristics FOR SELECT USING (public.is_company_member(company_id));
CREATE POLICY quality_inspections_member_select ON public.quality_inspections FOR SELECT USING (public.is_company_member(company_id));
CREATE POLICY inspection_results_member_select ON public.inspection_results FOR SELECT USING (public.is_company_member(company_id));

CREATE OR REPLACE FUNCTION public.create_inspection_plan(
  p_company_id uuid, p_plan_code text, p_name text, p_inspection_type text, p_item_id uuid DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['ADMIN','QUALITY','MANAGER']) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
  INSERT INTO public.inspection_plans(company_id, plan_code, name, item_id, inspection_type)
  VALUES(p_company_id, p_plan_code, p_name, p_item_id, p_inspection_type) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.add_inspection_characteristic(
  p_plan_id uuid, p_sequence_no integer, p_code text, p_name text, p_data_type text,
  p_nominal numeric DEFAULT NULL, p_lower numeric DEFAULT NULL, p_upper numeric DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_plan public.inspection_plans%ROWTYPE; v_id uuid;
BEGIN
  SELECT * INTO v_plan FROM public.inspection_plans WHERE id = p_plan_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inspection plan not found'; END IF;
  IF NOT public.has_company_role(v_plan.company_id, ARRAY['ADMIN','QUALITY','MANAGER']) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
  INSERT INTO public.inspection_characteristics(company_id, inspection_plan_id, sequence_no, characteristic_code, name, data_type, nominal_value, lower_limit, upper_limit)
  VALUES(v_plan.company_id, p_plan_id, p_sequence_no, p_code, p_name, p_data_type, p_nominal, p_lower, p_upper) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_quality_inspection(
  p_company_id uuid, p_inspection_number text, p_plan_id uuid, p_item_id uuid DEFAULT NULL, p_lot_id uuid DEFAULT NULL, p_source_type text DEFAULT NULL, p_source_id uuid DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['ADMIN','QUALITY','MANAGER','WAREHOUSE','PRODUCTION_OPERATOR']) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
  INSERT INTO public.quality_inspections(company_id, inspection_number, inspection_plan_id, item_id, lot_id, source_type, source_id)
  VALUES(p_company_id, p_inspection_number, p_plan_id, p_item_id, p_lot_id, p_source_type, p_source_id) RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_inspection_result(
  p_inspection_id uuid, p_characteristic_id uuid, p_numeric_value numeric DEFAULT NULL, p_boolean_value boolean DEFAULT NULL, p_text_value text DEFAULT NULL, p_note text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_insp public.quality_inspections%ROWTYPE; v_char public.inspection_characteristics%ROWTYPE; v_passed boolean; v_id uuid; v_failed_count integer;
BEGIN
  SELECT * INTO v_insp FROM public.quality_inspections WHERE id = p_inspection_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inspection not found'; END IF;
  SELECT * INTO v_char FROM public.inspection_characteristics WHERE id = p_characteristic_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Characteristic not found'; END IF;
  IF NOT public.has_company_role(v_insp.company_id, ARRAY['ADMIN','QUALITY','MANAGER','PRODUCTION_OPERATOR']) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;

  IF v_char.data_type = 'NUMERIC' THEN
    v_passed := (p_numeric_value IS NOT NULL)
      AND (v_char.lower_limit IS NULL OR p_numeric_value >= v_char.lower_limit)
      AND (v_char.upper_limit IS NULL OR p_numeric_value <= v_char.upper_limit);
  ELSIF v_char.data_type = 'BOOLEAN' THEN
    v_passed := COALESCE(p_boolean_value, false);
  ELSE
    v_passed := COALESCE(trim(p_text_value), '') <> '';
  END IF;

  INSERT INTO public.inspection_results(company_id, quality_inspection_id, characteristic_id, numeric_value, boolean_value, text_value, passed, note)
  VALUES(v_insp.company_id, p_inspection_id, p_characteristic_id, p_numeric_value, p_boolean_value, p_text_value, v_passed, p_note)
  ON CONFLICT(quality_inspection_id, characteristic_id) DO UPDATE SET
    numeric_value = EXCLUDED.numeric_value,
    boolean_value = EXCLUDED.boolean_value,
    text_value = EXCLUDED.text_value,
    passed = EXCLUDED.passed,
    note = EXCLUDED.note
  RETURNING id INTO v_id;

  SELECT count(*) INTO v_failed_count FROM public.inspection_results WHERE quality_inspection_id = p_inspection_id AND passed = false;
  UPDATE public.quality_inspections
  SET status = CASE WHEN v_failed_count > 0 THEN 'FAILED' ELSE 'PASSED' END,
      inspected_by = auth.uid(), inspected_at = now()
  WHERE id = p_inspection_id;

  RETURN v_id;
END;
$$;
