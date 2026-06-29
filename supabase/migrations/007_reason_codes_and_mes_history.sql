-- Reason code master data for scrap/downtime and hardened MES reporting.
-- Apply after 006_mes_operation_execution.sql

CREATE TABLE IF NOT EXISTS public.scrap_reason_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  code text NOT NULL,
  name text NOT NULL,
  category text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, code)
);
CREATE INDEX IF NOT EXISTS idx_scrap_reasons_company_active ON public.scrap_reason_codes(company_id, is_active, code);

CREATE TABLE IF NOT EXISTS public.downtime_reason_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  code text NOT NULL,
  name text NOT NULL,
  category text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, code)
);
CREATE INDEX IF NOT EXISTS idx_downtime_reasons_company_active ON public.downtime_reason_codes(company_id, is_active, code);

ALTER TABLE public.scrap_reason_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.downtime_reason_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS scrap_reason_codes_member_select ON public.scrap_reason_codes;
DROP POLICY IF EXISTS scrap_reason_codes_staff_insert ON public.scrap_reason_codes;
DROP POLICY IF EXISTS scrap_reason_codes_staff_update ON public.scrap_reason_codes;
CREATE POLICY scrap_reason_codes_member_select ON public.scrap_reason_codes FOR SELECT USING (public.is_company_member(company_id));
CREATE POLICY scrap_reason_codes_staff_insert ON public.scrap_reason_codes FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER','PLANNER']));
CREATE POLICY scrap_reason_codes_staff_update ON public.scrap_reason_codes FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER','PLANNER'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER','PLANNER']));

DROP POLICY IF EXISTS downtime_reason_codes_member_select ON public.downtime_reason_codes;
DROP POLICY IF EXISTS downtime_reason_codes_staff_insert ON public.downtime_reason_codes;
DROP POLICY IF EXISTS downtime_reason_codes_staff_update ON public.downtime_reason_codes;
CREATE POLICY downtime_reason_codes_member_select ON public.downtime_reason_codes FOR SELECT USING (public.is_company_member(company_id));
CREATE POLICY downtime_reason_codes_staff_insert ON public.downtime_reason_codes FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER','PLANNER']));
CREATE POLICY downtime_reason_codes_staff_update ON public.downtime_reason_codes FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER','PLANNER'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER','PLANNER']));

CREATE OR REPLACE FUNCTION public.seed_reason_codes(p_company_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['ADMIN','QUALITY','MANAGER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  INSERT INTO public.scrap_reason_codes(company_id, code, name, category)
  VALUES
    (p_company_id, 'SETUP', 'Setup scrap', 'PROCESS'),
    (p_company_id, 'MAT_DEFECT', 'Material defect', 'MATERIAL'),
    (p_company_id, 'TOOL_WEAR', 'Tool wear', 'TOOLING'),
    (p_company_id, 'DIM_NOK', 'Dimension out of tolerance', 'QUALITY'),
    (p_company_id, 'SURFACE_NOK', 'Surface defect', 'QUALITY'),
    (p_company_id, 'OPERATOR_ERR', 'Operator error', 'PROCESS')
  ON CONFLICT(company_id, code) DO NOTHING;

  INSERT INTO public.downtime_reason_codes(company_id, code, name, category)
  VALUES
    (p_company_id, 'MACHINE_DOWN', 'Machine breakdown', 'MACHINE'),
    (p_company_id, 'TOOL_CHANGE', 'Tool change', 'TOOLING'),
    (p_company_id, 'NO_MATERIAL', 'No material', 'SUPPLY'),
    (p_company_id, 'QUALITY_CHECK', 'Quality check hold', 'QUALITY'),
    (p_company_id, 'SHIFT_BREAK', 'Shift break', 'LABOR'),
    (p_company_id, 'MAINTENANCE', 'Maintenance', 'MAINTENANCE')
  ON CONFLICT(company_id, code) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.pause_production_operation(
  p_operation_id uuid,
  p_reason_code text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_op public.production_order_operations%ROWTYPE;
  v_event_id uuid;
BEGIN
  SELECT * INTO v_op FROM public.production_order_operations WHERE id = p_operation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order operation not found'; END IF;

  IF NOT public.has_company_role(v_op.company_id, ARRAY['ADMIN','PRODUCTION_OPERATOR','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_op.status <> 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'Only IN_PROGRESS operation can be paused';
  END IF;

  IF trim(COALESCE(p_reason_code, '')) <> '' AND NOT EXISTS (
    SELECT 1 FROM public.downtime_reason_codes
    WHERE company_id = v_op.company_id AND code = trim(p_reason_code) AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Invalid downtime reason code %', p_reason_code;
  END IF;

  UPDATE public.production_order_operations SET status = 'PAUSED' WHERE id = v_op.id;

  INSERT INTO public.production_operation_events(
    company_id, production_order_operation_id, event_type, operator_id, machine_id, reason_code, note
  ) VALUES (
    v_op.company_id, v_op.id, 'PAUSE', auth.uid(), v_op.machine_id, NULLIF(trim(COALESCE(p_reason_code, '')), ''), p_note
  ) RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.report_production_operation(
  p_operation_id uuid,
  p_quantity_good numeric DEFAULT 0,
  p_quantity_scrap numeric DEFAULT 0,
  p_reason_code text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_complete boolean DEFAULT false
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_op public.production_order_operations%ROWTYPE;
  v_next_op_id uuid;
  v_event_id uuid;
BEGIN
  IF p_quantity_good < 0 OR p_quantity_scrap < 0 THEN
    RAISE EXCEPTION 'Reported quantities cannot be negative';
  END IF;
  IF p_quantity_good = 0 AND p_quantity_scrap = 0 AND NOT p_complete THEN
    RAISE EXCEPTION 'Nothing to report';
  END IF;

  SELECT * INTO v_op FROM public.production_order_operations WHERE id = p_operation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order operation not found'; END IF;

  IF NOT public.has_company_role(v_op.company_id, ARRAY['ADMIN','PRODUCTION_OPERATOR','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_op.status NOT IN ('IN_PROGRESS','PAUSED','READY','PENDING') THEN
    RAISE EXCEPTION 'Operation status % cannot be reported', v_op.status;
  END IF;

  IF p_quantity_scrap > 0 THEN
    IF trim(COALESCE(p_reason_code, '')) = '' THEN
      RAISE EXCEPTION 'Scrap reason code is required when scrap quantity is reported';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.scrap_reason_codes
      WHERE company_id = v_op.company_id AND code = trim(p_reason_code) AND is_active = true
    ) THEN
      RAISE EXCEPTION 'Invalid scrap reason code %', p_reason_code;
    END IF;
  END IF;

  UPDATE public.production_order_operations
  SET completed_quantity = completed_quantity + p_quantity_good,
      scrap_quantity = scrap_quantity + p_quantity_scrap,
      status = CASE WHEN p_complete THEN 'COMPLETED' ELSE status END,
      completed_at = CASE WHEN p_complete THEN now() ELSE completed_at END
  WHERE id = v_op.id;

  INSERT INTO public.production_operation_events(
    company_id, production_order_operation_id, event_type, operator_id, machine_id,
    quantity_good, quantity_scrap, reason_code, note
  ) VALUES (
    v_op.company_id, v_op.id,
    CASE WHEN p_complete THEN 'COMPLETE' WHEN p_quantity_scrap > 0 THEN 'REPORT_SCRAP' ELSE 'REPORT_QTY' END,
    auth.uid(), v_op.machine_id, p_quantity_good, p_quantity_scrap, NULLIF(trim(COALESCE(p_reason_code, '')), ''), p_note
  ) RETURNING id INTO v_event_id;

  IF p_complete THEN
    IF v_op.machine_id IS NOT NULL THEN
      UPDATE public.machines SET status = 'AVAILABLE' WHERE id = v_op.machine_id AND status = 'RUNNING';
    END IF;

    SELECT id INTO v_next_op_id
    FROM public.production_order_operations
    WHERE production_order_id = v_op.production_order_id
      AND sequence_no > v_op.sequence_no
      AND status = 'PENDING'
    ORDER BY sequence_no
    LIMIT 1;

    IF v_next_op_id IS NOT NULL THEN
      UPDATE public.production_order_operations SET status = 'READY' WHERE id = v_next_op_id;
    END IF;
  END IF;

  RETURN v_event_id;
END;
$$;
