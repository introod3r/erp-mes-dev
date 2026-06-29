-- Backflush workflow foundation.
-- Apply after 012_correction_approval_workflow.sql

CREATE OR REPLACE FUNCTION public.backflush_production_order(
  p_production_order_id uuid,
  p_quantity_basis numeric DEFAULT NULL
)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po public.production_orders%ROWTYPE;
  v_mat public.production_order_materials%ROWTYPE;
  v_qty numeric(18,4);
  v_reserved_before numeric(18,4);
  v_to_consume numeric(18,4);
  v_total numeric(18,4) := 0;
BEGIN
  SELECT * INTO v_po FROM public.production_orders WHERE id = p_production_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order not found'; END IF;
  IF NOT public.has_company_role(v_po.company_id, ARRAY['ADMIN','PLANNER','PRODUCTION_OPERATOR','WAREHOUSE']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF v_po.status NOT IN ('RELEASED','IN_PROGRESS') THEN
    RAISE EXCEPTION 'Backflush allowed only for RELEASED or IN_PROGRESS orders';
  END IF;

  FOR v_mat IN
    SELECT * FROM public.production_order_materials
    WHERE production_order_id = p_production_order_id AND issue_method = 'BACKFLUSH'
    ORDER BY operation_sequence NULLS LAST, created_at
    FOR UPDATE
  LOOP
    IF p_quantity_basis IS NULL THEN
      v_qty := GREATEST(v_mat.planned_qty - v_mat.consumed_qty, 0);
    ELSE
      v_qty := GREATEST((v_mat.planned_qty / v_po.planned_quantity) * p_quantity_basis - v_mat.consumed_qty, 0);
    END IF;

    IF v_qty <= 0 THEN CONTINUE; END IF;

    v_reserved_before := v_mat.reserved_qty;
    -- Reserve available stock for this backflush item, from any warehouse/lot.
    PERFORM public.reserve_production_order_materials(p_production_order_id, NULL);

    SELECT * INTO v_mat FROM public.production_order_materials WHERE id = v_mat.id FOR UPDATE;
    v_to_consume := LEAST(v_qty, v_mat.reserved_qty - v_mat.consumed_qty);
    IF v_to_consume <= 0 THEN
      RAISE EXCEPTION 'Insufficient reserved/available stock for backflush item %', v_mat.item_id;
    END IF;

    PERFORM public.consume_production_material(v_mat.id, v_to_consume);
    v_total := v_total + v_to_consume;
  END LOOP;

  RETURN v_total;
END;
$$;
