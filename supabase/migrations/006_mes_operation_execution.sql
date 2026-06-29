-- MES-lite operation execution functions.
-- Apply after 005_consumption_and_receipts.sql

CREATE OR REPLACE FUNCTION public.start_production_operation(
  p_operation_id uuid,
  p_machine_id uuid DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_op public.production_order_operations%ROWTYPE;
  v_po public.production_orders%ROWTYPE;
  v_event_id uuid;
BEGIN
  SELECT * INTO v_op FROM public.production_order_operations WHERE id = p_operation_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order operation not found'; END IF;

  SELECT * INTO v_po FROM public.production_orders WHERE id = v_op.production_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order not found'; END IF;

  IF NOT public.has_company_role(v_op.company_id, ARRAY['ADMIN','PRODUCTION_OPERATOR','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_po.status NOT IN ('RELEASED','IN_PROGRESS') THEN
    RAISE EXCEPTION 'Can start operation only for RELEASED or IN_PROGRESS orders';
  END IF;

  IF v_op.status NOT IN ('READY','PENDING','PAUSED') THEN
    RAISE EXCEPTION 'Operation status % cannot be started', v_op.status;
  END IF;

  IF p_machine_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.machines
      WHERE id = p_machine_id AND company_id = v_op.company_id AND work_center_id = v_op.work_center_id
    ) THEN
      RAISE EXCEPTION 'Machine does not belong to operation work center';
    END IF;

    UPDATE public.machines
    SET status = 'RUNNING'
    WHERE id = p_machine_id AND status IN ('AVAILABLE','RUNNING');
  END IF;

  UPDATE public.production_order_operations
  SET status = 'IN_PROGRESS',
      machine_id = COALESCE(p_machine_id, machine_id),
      started_at = COALESCE(started_at, now())
  WHERE id = v_op.id;

  UPDATE public.production_orders
  SET status = 'IN_PROGRESS',
      actual_start_date = COALESCE(actual_start_date, now()),
      updated_at = now()
  WHERE id = v_po.id;

  INSERT INTO public.production_operation_events(
    company_id, production_order_operation_id, event_type, operator_id, machine_id
  ) VALUES (
    v_op.company_id, v_op.id, CASE WHEN v_op.status = 'PAUSED' THEN 'RESUME' ELSE 'START' END, auth.uid(), COALESCE(p_machine_id, v_op.machine_id)
  ) RETURNING id INTO v_event_id;

  RETURN v_event_id;
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

  UPDATE public.production_order_operations SET status = 'PAUSED' WHERE id = v_op.id;

  INSERT INTO public.production_operation_events(
    company_id, production_order_operation_id, event_type, operator_id, machine_id, reason_code, note
  ) VALUES (
    v_op.company_id, v_op.id, 'PAUSE', auth.uid(), v_op.machine_id, p_reason_code, p_note
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
    auth.uid(), v_op.machine_id, p_quantity_good, p_quantity_scrap, p_reason_code, p_note
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

CREATE OR REPLACE FUNCTION public.stop_production_operation(
  p_operation_id uuid,
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

  IF v_op.status NOT IN ('IN_PROGRESS','PAUSED') THEN
    RAISE EXCEPTION 'Only IN_PROGRESS or PAUSED operation can be stopped';
  END IF;

  UPDATE public.production_order_operations SET status = 'READY' WHERE id = v_op.id;
  IF v_op.machine_id IS NOT NULL THEN
    UPDATE public.machines SET status = 'AVAILABLE' WHERE id = v_op.machine_id AND status = 'RUNNING';
  END IF;

  INSERT INTO public.production_operation_events(
    company_id, production_order_operation_id, event_type, operator_id, machine_id, note
  ) VALUES (
    v_op.company_id, v_op.id, 'STOP', auth.uid(), v_op.machine_id, p_note
  ) RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;
