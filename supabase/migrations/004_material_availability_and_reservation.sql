-- Material availability and reserve-all workflow for released production orders.
-- Apply after 003_multilevel_bom_release.sql

CREATE OR REPLACE FUNCTION public.get_production_order_material_availability(p_production_order_id uuid)
RETURNS TABLE (
  production_order_material_id uuid,
  item_id uuid,
  item_code text,
  item_name text,
  planned_qty numeric,
  reserved_qty numeric,
  consumed_qty numeric,
  uom_id uuid,
  uom_code text,
  quantity_on_hand numeric,
  quantity_reserved_total numeric,
  quantity_available numeric,
  remaining_to_reserve numeric,
  shortage_qty numeric
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    pom.id AS production_order_material_id,
    pom.item_id,
    i.item_code,
    i.name AS item_name,
    pom.planned_qty,
    pom.reserved_qty,
    pom.consumed_qty,
    pom.uom_id,
    u.code AS uom_code,
    COALESCE(SUM(sb.quantity_on_hand), 0)::numeric AS quantity_on_hand,
    COALESCE(SUM(sb.quantity_reserved), 0)::numeric AS quantity_reserved_total,
    COALESCE(SUM(sb.quantity_on_hand - sb.quantity_reserved), 0)::numeric AS quantity_available,
    GREATEST(pom.planned_qty - pom.reserved_qty, 0)::numeric AS remaining_to_reserve,
    GREATEST((pom.planned_qty - pom.reserved_qty) - COALESCE(SUM(sb.quantity_on_hand - sb.quantity_reserved), 0), 0)::numeric AS shortage_qty
  FROM public.production_order_materials pom
  JOIN public.production_orders po ON po.id = pom.production_order_id
  JOIN public.items i ON i.id = pom.item_id
  JOIN public.units_of_measure u ON u.id = pom.uom_id
  LEFT JOIN public.stock_balances sb ON sb.company_id = pom.company_id
    AND sb.item_id = pom.item_id
  WHERE pom.production_order_id = p_production_order_id
    AND public.is_company_member(pom.company_id)
  GROUP BY pom.id, pom.item_id, i.item_code, i.name, pom.planned_qty, pom.reserved_qty, pom.consumed_qty, pom.uom_id, u.code
  ORDER BY i.item_code;
$$;

CREATE OR REPLACE FUNCTION public.reserve_production_order_materials(
  p_production_order_id uuid,
  p_warehouse_id uuid DEFAULT NULL
)
RETURNS TABLE (
  production_order_material_id uuid,
  item_id uuid,
  requested_qty numeric,
  reserved_now_qty numeric,
  shortage_qty numeric
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po public.production_orders%ROWTYPE;
  v_mat public.production_order_materials%ROWTYPE;
  v_bal public.stock_balances%ROWTYPE;
  v_need numeric(18,4);
  v_take numeric(18,4);
  v_reserved numeric(18,4);
BEGIN
  SELECT * INTO v_po FROM public.production_orders WHERE id = p_production_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order not found'; END IF;

  IF NOT public.has_company_role(v_po.company_id, ARRAY['ADMIN','PLANNER','WAREHOUSE']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_po.status NOT IN ('RELEASED','IN_PROGRESS') THEN
    RAISE EXCEPTION 'Can reserve materials only for RELEASED or IN_PROGRESS orders';
  END IF;

  IF p_warehouse_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.warehouses WHERE id = p_warehouse_id AND company_id = v_po.company_id
  ) THEN
    RAISE EXCEPTION 'Warehouse does not belong to production order company';
  END IF;

  FOR v_mat IN
    SELECT *
    FROM public.production_order_materials
    WHERE production_order_id = p_production_order_id
    ORDER BY operation_sequence NULLS LAST, created_at
    FOR UPDATE
  LOOP
    v_need := GREATEST(v_mat.planned_qty - v_mat.reserved_qty, 0);
    v_reserved := 0;

    IF v_need > 0 THEN
      FOR v_bal IN
        SELECT *
        FROM public.stock_balances
        WHERE company_id = v_po.company_id
          AND item_id = v_mat.item_id
          AND (p_warehouse_id IS NULL OR warehouse_id = p_warehouse_id)
          AND quantity_on_hand > quantity_reserved
        ORDER BY warehouse_id, location_id NULLS FIRST, lot_id NULLS FIRST, updated_at
        FOR UPDATE SKIP LOCKED
      LOOP
        EXIT WHEN v_need <= 0;
        v_take := LEAST(v_need, v_bal.quantity_on_hand - v_bal.quantity_reserved);
        IF v_take <= 0 THEN CONTINUE; END IF;

        UPDATE public.stock_balances
        SET quantity_reserved = quantity_reserved + v_take,
            updated_at = now()
        WHERE id = v_bal.id;

        INSERT INTO public.inventory_reservations(
          company_id, production_order_id, production_order_material_id, item_id,
          warehouse_id, location_id, lot_id, reserved_qty, status
        ) VALUES (
          v_po.company_id, v_po.id, v_mat.id, v_mat.item_id,
          v_bal.warehouse_id, v_bal.location_id, v_bal.lot_id, v_take, 'ACTIVE'
        );

        v_need := v_need - v_take;
        v_reserved := v_reserved + v_take;
      END LOOP;

      IF v_reserved > 0 THEN
        UPDATE public.production_order_materials
        SET reserved_qty = reserved_qty + v_reserved
        WHERE id = v_mat.id;
      END IF;
    END IF;

    production_order_material_id := v_mat.id;
    item_id := v_mat.item_id;
    requested_qty := GREATEST(v_mat.planned_qty - v_mat.reserved_qty, 0);
    reserved_now_qty := v_reserved;
    shortage_qty := GREATEST(v_need, 0);
    RETURN NEXT;
  END LOOP;
END;
$$;
