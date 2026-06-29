-- Multi-level BOM explosion and hardened production order release.
-- Apply after 001_core_erp_mes_schema.sql and 002_onboarding_and_seed_helpers.sql

DROP FUNCTION IF EXISTS public.explode_bom_requirements(uuid, uuid, numeric, date);

CREATE OR REPLACE FUNCTION public.explode_bom_requirements(
  p_company_id uuid,
  p_parent_item_id uuid,
  p_quantity numeric,
  p_effective_date date DEFAULT CURRENT_DATE
)
RETURNS TABLE (
  level integer,
  component_item_id uuid,
  required_qty numeric,
  uom_id uuid,
  source_bom_line_id uuid,
  issue_method text,
  operation_sequence integer,
  path uuid[]
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_root_bom_count integer;
  v_cycle_count integer;
BEGIN
  IF p_quantity <= 0 THEN
    RAISE EXCEPTION 'Explosion quantity must be positive';
  END IF;

  SELECT count(*) INTO v_root_bom_count
  FROM public.boms b
  WHERE b.company_id = p_company_id
    AND b.parent_item_id = p_parent_item_id
    AND b.status = 'ACTIVE'
    AND b.is_default = true
    AND b.valid_from <= p_effective_date
    AND (b.valid_to IS NULL OR b.valid_to >= p_effective_date);

  IF v_root_bom_count = 0 THEN
    RAISE EXCEPTION 'No active default BOM found for item %', p_parent_item_id;
  ELSIF v_root_bom_count > 1 THEN
    RAISE EXCEPTION 'More than one active default BOM found for item %', p_parent_item_id;
  END IF;

  -- Detect cycles reachable from the selected root BOM before returning requirements.
  WITH RECURSIVE cycle_walk AS (
    SELECT
      b.parent_item_id,
      bl.component_item_id,
      ARRAY[b.parent_item_id, bl.component_item_id]::uuid[] AS path,
      (bl.component_item_id = b.parent_item_id) AS is_cycle
    FROM public.boms b
    JOIN public.bom_lines bl ON bl.bom_id = b.id
    WHERE b.company_id = p_company_id
      AND b.parent_item_id = p_parent_item_id
      AND b.status = 'ACTIVE'
      AND b.is_default = true
      AND b.valid_from <= p_effective_date
      AND (b.valid_to IS NULL OR b.valid_to >= p_effective_date)

    UNION ALL

    SELECT
      cb.parent_item_id,
      cbl.component_item_id,
      cw.path || cbl.component_item_id,
      cbl.component_item_id = ANY(cw.path)
    FROM cycle_walk cw
    JOIN public.boms cb ON cb.parent_item_id = cw.component_item_id
      AND cb.company_id = p_company_id
      AND cb.status = 'ACTIVE'
      AND cb.is_default = true
      AND cb.valid_from <= p_effective_date
      AND (cb.valid_to IS NULL OR cb.valid_to >= p_effective_date)
    JOIN public.bom_lines cbl ON cbl.bom_id = cb.id
    WHERE NOT cw.is_cycle
      AND array_length(cw.path, 1) < 50
  )
  SELECT count(*) INTO v_cycle_count FROM cycle_walk WHERE is_cycle;

  IF v_cycle_count > 0 THEN
    RAISE EXCEPTION 'BOM cycle detected for root item %', p_parent_item_id;
  END IF;

  RETURN QUERY
  WITH RECURSIVE tree AS (
    SELECT
      1 AS level,
      bl.component_item_id,
      ((p_quantity / b.output_quantity) * bl.quantity_per * (1 + bl.scrap_factor_percent / 100.0))::numeric AS required_qty,
      bl.uom_id,
      bl.id AS source_bom_line_id,
      bl.issue_method,
      bl.operation_sequence,
      ARRAY[b.parent_item_id, bl.component_item_id]::uuid[] AS path,
      child_bom.id AS child_bom_id
    FROM public.boms b
    JOIN public.bom_lines bl ON bl.bom_id = b.id
    LEFT JOIN LATERAL (
      SELECT cb.id
      FROM public.boms cb
      WHERE cb.company_id = p_company_id
        AND cb.parent_item_id = bl.component_item_id
        AND cb.status = 'ACTIVE'
        AND cb.is_default = true
        AND cb.valid_from <= p_effective_date
        AND (cb.valid_to IS NULL OR cb.valid_to >= p_effective_date)
      ORDER BY cb.valid_from DESC
      LIMIT 1
    ) child_bom ON true
    WHERE b.company_id = p_company_id
      AND b.parent_item_id = p_parent_item_id
      AND b.status = 'ACTIVE'
      AND b.is_default = true
      AND b.valid_from <= p_effective_date
      AND (b.valid_to IS NULL OR b.valid_to >= p_effective_date)

    UNION ALL

    SELECT
      t.level + 1,
      bl.component_item_id,
      ((t.required_qty / b.output_quantity) * bl.quantity_per * (1 + bl.scrap_factor_percent / 100.0))::numeric AS required_qty,
      bl.uom_id,
      bl.id AS source_bom_line_id,
      bl.issue_method,
      bl.operation_sequence,
      t.path || bl.component_item_id,
      child_bom.id AS child_bom_id
    FROM tree t
    JOIN public.boms b ON b.id = t.child_bom_id
    JOIN public.bom_lines bl ON bl.bom_id = b.id
    LEFT JOIN LATERAL (
      SELECT cb.id
      FROM public.boms cb
      WHERE cb.company_id = p_company_id
        AND cb.parent_item_id = bl.component_item_id
        AND cb.status = 'ACTIVE'
        AND cb.is_default = true
        AND cb.valid_from <= p_effective_date
        AND (cb.valid_to IS NULL OR cb.valid_to >= p_effective_date)
      ORDER BY cb.valid_from DESC
      LIMIT 1
    ) child_bom ON true
    WHERE array_length(t.path, 1) < 50
  )
  SELECT
    t.level,
    t.component_item_id,
    ROUND(t.required_qty, 4),
    t.uom_id,
    t.source_bom_line_id,
    t.issue_method,
    t.operation_sequence,
    t.path
  FROM tree t
  WHERE t.child_bom_id IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_production_order(p_production_order_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po public.production_orders%ROWTYPE;
  v_bom_id uuid;
  v_bom_count integer;
  v_routing_id uuid;
  v_routing_count integer;
  v_material_count integer;
BEGIN
  SELECT * INTO v_po FROM public.production_orders WHERE id = p_production_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order not found'; END IF;

  IF NOT public.has_company_role(v_po.company_id, ARRAY['ADMIN','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_po.status <> 'PLANNED' THEN
    RAISE EXCEPTION 'Only PLANNED orders can be released';
  END IF;

  IF EXISTS (SELECT 1 FROM public.production_order_materials WHERE production_order_id = v_po.id)
     OR EXISTS (SELECT 1 FROM public.production_order_operations WHERE production_order_id = v_po.id) THEN
    RAISE EXCEPTION 'Production order already has material/operation snapshots';
  END IF;

  IF v_po.bom_id IS NOT NULL THEN
    SELECT id INTO v_bom_id
    FROM public.boms
    WHERE id = v_po.bom_id
      AND company_id = v_po.company_id
      AND parent_item_id = v_po.item_id
      AND status = 'ACTIVE'
      AND valid_from <= CURRENT_DATE
      AND (valid_to IS NULL OR valid_to >= CURRENT_DATE);
    IF v_bom_id IS NULL THEN RAISE EXCEPTION 'Selected BOM is not active/valid for this order item'; END IF;
  ELSE
    SELECT count(*) INTO v_bom_count
    FROM public.boms
    WHERE company_id = v_po.company_id
      AND parent_item_id = v_po.item_id
      AND status = 'ACTIVE'
      AND is_default = true
      AND valid_from <= CURRENT_DATE
      AND (valid_to IS NULL OR valid_to >= CURRENT_DATE);

    IF v_bom_count = 0 THEN RAISE EXCEPTION 'No active default BOM found'; END IF;
    IF v_bom_count > 1 THEN RAISE EXCEPTION 'More than one active default BOM found'; END IF;

    SELECT id INTO v_bom_id
    FROM public.boms
    WHERE company_id = v_po.company_id
      AND parent_item_id = v_po.item_id
      AND status = 'ACTIVE'
      AND is_default = true
      AND valid_from <= CURRENT_DATE
      AND (valid_to IS NULL OR valid_to >= CURRENT_DATE)
    LIMIT 1;
  END IF;

  IF v_po.routing_id IS NOT NULL THEN
    SELECT id INTO v_routing_id
    FROM public.routings
    WHERE id = v_po.routing_id
      AND company_id = v_po.company_id
      AND item_id = v_po.item_id
      AND status = 'ACTIVE'
      AND valid_from <= CURRENT_DATE
      AND (valid_to IS NULL OR valid_to >= CURRENT_DATE);
    IF v_routing_id IS NULL THEN RAISE EXCEPTION 'Selected routing is not active/valid for this order item'; END IF;
  ELSE
    SELECT count(*) INTO v_routing_count
    FROM public.routings
    WHERE company_id = v_po.company_id
      AND item_id = v_po.item_id
      AND status = 'ACTIVE'
      AND is_default = true
      AND valid_from <= CURRENT_DATE
      AND (valid_to IS NULL OR valid_to >= CURRENT_DATE);

    IF v_routing_count > 1 THEN RAISE EXCEPTION 'More than one active default routing found'; END IF;
    IF v_routing_count = 1 THEN
      SELECT id INTO v_routing_id
      FROM public.routings
      WHERE company_id = v_po.company_id
        AND item_id = v_po.item_id
        AND status = 'ACTIVE'
        AND is_default = true
        AND valid_from <= CURRENT_DATE
        AND (valid_to IS NULL OR valid_to >= CURRENT_DATE)
      LIMIT 1;
    END IF;
  END IF;

  INSERT INTO public.production_order_materials(
    company_id, production_order_id, item_id, planned_qty, uom_id, source_bom_line_id, issue_method, operation_sequence
  )
  SELECT
    v_po.company_id,
    v_po.id,
    req.component_item_id,
    SUM(req.required_qty),
    req.uom_id,
    CASE WHEN count(DISTINCT req.source_bom_line_id) = 1 THEN min(req.source_bom_line_id) ELSE NULL END,
    req.issue_method,
    req.operation_sequence
  FROM public.explode_bom_requirements(v_po.company_id, v_po.item_id, v_po.planned_quantity, CURRENT_DATE) req
  GROUP BY req.component_item_id, req.uom_id, req.issue_method, req.operation_sequence;

  SELECT count(*) INTO v_material_count FROM public.production_order_materials WHERE production_order_id = v_po.id;
  IF v_material_count = 0 THEN RAISE EXCEPTION 'BOM explosion returned no material requirements'; END IF;

  IF v_routing_id IS NOT NULL THEN
    INSERT INTO public.production_order_operations(
      company_id, production_order_id, sequence_no, operation_code, operation_name,
      work_center_id, planned_setup_time_minutes, planned_run_time_minutes, planned_quantity, status
    )
    SELECT
      v_po.company_id,
      v_po.id,
      ro.sequence_no,
      ro.operation_code,
      ro.operation_name,
      ro.work_center_id,
      ro.setup_time_minutes,
      ro.run_time_minutes_per_unit * v_po.planned_quantity,
      v_po.planned_quantity,
      CASE WHEN ro.sequence_no = (SELECT MIN(sequence_no) FROM public.routing_operations WHERE routing_id = v_routing_id)
           THEN 'READY' ELSE 'PENDING' END
    FROM public.routing_operations ro
    WHERE ro.routing_id = v_routing_id
    ORDER BY ro.sequence_no;
  END IF;

  UPDATE public.production_orders
  SET status = 'RELEASED', bom_id = v_bom_id, routing_id = v_routing_id, updated_at = now()
  WHERE id = v_po.id;
END;
$$;
