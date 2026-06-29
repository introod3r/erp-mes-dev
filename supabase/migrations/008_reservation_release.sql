-- Reservation release/cancellation workflow.
-- Apply after 007_reason_codes_and_mes_history.sql

ALTER TABLE public.inventory_reservations
ADD COLUMN IF NOT EXISTS released_qty numeric(18,4) NOT NULL DEFAULT 0 CHECK (released_qty >= 0);

-- Replace consumption function so released reservation quantities cannot be consumed.
CREATE OR REPLACE FUNCTION public.consume_production_material(
  p_production_order_material_id uuid,
  p_qty numeric
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pom public.production_order_materials%ROWTYPE;
  v_po public.production_orders%ROWTYPE;
  v_res public.inventory_reservations%ROWTYPE;
  v_balance public.stock_balances%ROWTYPE;
  v_remaining numeric(18,4);
  v_take numeric(18,4);
  v_tx_id uuid;
  v_line_id uuid;
BEGIN
  IF p_qty <= 0 THEN
    RAISE EXCEPTION 'Consumption quantity must be positive';
  END IF;

  SELECT * INTO v_pom
  FROM public.production_order_materials
  WHERE id = p_production_order_material_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Production order material not found'; END IF;

  SELECT * INTO v_po
  FROM public.production_orders
  WHERE id = v_pom.production_order_id
  FOR UPDATE;

  IF NOT public.has_company_role(v_pom.company_id, ARRAY['ADMIN','WAREHOUSE','PRODUCTION_OPERATOR','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_po.status NOT IN ('RELEASED','IN_PROGRESS') THEN
    RAISE EXCEPTION 'Can consume materials only for RELEASED or IN_PROGRESS orders';
  END IF;

  IF p_qty > (v_pom.reserved_qty - v_pom.consumed_qty) THEN
    RAISE EXCEPTION 'Consumption quantity exceeds remaining reserved quantity. Reserve material first.';
  END IF;

  INSERT INTO public.inventory_transactions(
    company_id, transaction_type, source_type, source_id, reference_number, note, created_by
  ) VALUES (
    v_pom.company_id, 'PRODUCTION_ISSUE', 'PRODUCTION_ORDER', v_po.id, v_po.order_number,
    'Material consumption for production order', auth.uid()
  ) RETURNING id INTO v_tx_id;

  v_remaining := p_qty;

  FOR v_res IN
    SELECT *
    FROM public.inventory_reservations
    WHERE production_order_material_id = v_pom.id
      AND status IN ('ACTIVE','PARTIALLY_CONSUMED')
      AND reserved_qty > consumed_qty + released_qty
    ORDER BY created_at
    FOR UPDATE
  LOOP
    EXIT WHEN v_remaining <= 0;
    v_take := LEAST(v_remaining, v_res.reserved_qty - v_res.consumed_qty - v_res.released_qty);

    SELECT * INTO v_balance
    FROM public.stock_balances
    WHERE company_id = v_pom.company_id
      AND item_id = v_pom.item_id
      AND warehouse_id = v_res.warehouse_id
      AND location_id IS NOT DISTINCT FROM v_res.location_id
      AND lot_id IS NOT DISTINCT FROM v_res.lot_id
    FOR UPDATE;

    IF NOT FOUND THEN RAISE EXCEPTION 'Stock balance not found for reservation %', v_res.id; END IF;
    IF v_balance.quantity_on_hand < v_take OR v_balance.quantity_reserved < v_take THEN
      RAISE EXCEPTION 'Stock balance inconsistency for item %', v_pom.item_id;
    END IF;

    UPDATE public.stock_balances
    SET quantity_on_hand = quantity_on_hand - v_take,
        quantity_reserved = quantity_reserved - v_take,
        updated_at = now()
    WHERE id = v_balance.id;

    INSERT INTO public.inventory_transaction_lines(
      company_id, transaction_id, item_id, lot_id,
      from_warehouse_id, from_location_id, quantity, uom_id,
      production_order_id, production_order_material_id
    ) VALUES (
      v_pom.company_id, v_tx_id, v_pom.item_id, v_res.lot_id,
      v_res.warehouse_id, v_res.location_id, v_take, v_pom.uom_id,
      v_po.id, v_pom.id
    ) RETURNING id INTO v_line_id;

    INSERT INTO public.production_consumptions(
      company_id, production_order_id, production_order_material_id, item_id, lot_id,
      warehouse_id, location_id, quantity, uom_id, inventory_transaction_line_id, consumed_by
    ) VALUES (
      v_pom.company_id, v_po.id, v_pom.id, v_pom.item_id, v_res.lot_id,
      v_res.warehouse_id, v_res.location_id, v_take, v_pom.uom_id, v_line_id, auth.uid()
    );

    UPDATE public.inventory_reservations
    SET consumed_qty = consumed_qty + v_take,
        status = CASE
          WHEN consumed_qty + v_take + released_qty >= reserved_qty THEN 'CONSUMED'
          ELSE 'PARTIALLY_CONSUMED'
        END
    WHERE id = v_res.id;

    v_remaining := v_remaining - v_take;
  END LOOP;

  IF v_remaining > 0 THEN
    RAISE EXCEPTION 'Reserved material disappeared during consumption';
  END IF;

  UPDATE public.production_order_materials
  SET consumed_qty = consumed_qty + p_qty,
      issued_qty = issued_qty + p_qty
  WHERE id = v_pom.id;

  IF v_po.status = 'RELEASED' THEN
    UPDATE public.production_orders
    SET status = 'IN_PROGRESS', actual_start_date = COALESCE(actual_start_date, now()), updated_at = now()
    WHERE id = v_po.id;
  END IF;

  RETURN v_tx_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_inventory_reservation(
  p_reservation_id uuid,
  p_qty numeric DEFAULT NULL
)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_res public.inventory_reservations%ROWTYPE;
  v_balance public.stock_balances%ROWTYPE;
  v_releasable numeric(18,4);
  v_qty numeric(18,4);
BEGIN
  SELECT * INTO v_res
  FROM public.inventory_reservations
  WHERE id = p_reservation_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Reservation not found'; END IF;

  IF NOT public.has_company_role(v_res.company_id, ARRAY['ADMIN','WAREHOUSE','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_res.status NOT IN ('ACTIVE','PARTIALLY_CONSUMED') THEN
    RAISE EXCEPTION 'Only active/partially consumed reservations can be released';
  END IF;

  v_releasable := v_res.reserved_qty - v_res.consumed_qty - v_res.released_qty;
  IF v_releasable <= 0 THEN
    RAISE EXCEPTION 'Reservation has no releasable quantity';
  END IF;

  v_qty := COALESCE(p_qty, v_releasable);
  IF v_qty <= 0 OR v_qty > v_releasable THEN
    RAISE EXCEPTION 'Invalid release quantity';
  END IF;

  SELECT * INTO v_balance
  FROM public.stock_balances
  WHERE company_id = v_res.company_id
    AND item_id = v_res.item_id
    AND warehouse_id = v_res.warehouse_id
    AND location_id IS NOT DISTINCT FROM v_res.location_id
    AND lot_id IS NOT DISTINCT FROM v_res.lot_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Stock balance not found'; END IF;
  IF v_balance.quantity_reserved < v_qty THEN RAISE EXCEPTION 'Stock reserved quantity inconsistency'; END IF;

  UPDATE public.stock_balances
  SET quantity_reserved = quantity_reserved - v_qty,
      updated_at = now()
  WHERE id = v_balance.id;

  UPDATE public.production_order_materials
  SET reserved_qty = reserved_qty - v_qty
  WHERE id = v_res.production_order_material_id;

  UPDATE public.inventory_reservations
  SET released_qty = released_qty + v_qty,
      status = CASE
        WHEN consumed_qty > 0 AND consumed_qty + released_qty + v_qty >= reserved_qty THEN 'CONSUMED'
        WHEN consumed_qty = 0 AND released_qty + v_qty >= reserved_qty THEN 'RELEASED'
        ELSE status
      END,
      released_at = CASE WHEN released_qty + v_qty >= reserved_qty THEN now() ELSE released_at END
  WHERE id = v_res.id;

  RETURN v_qty;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_production_order_reservations(p_production_order_id uuid)
RETURNS numeric LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po public.production_orders%ROWTYPE;
  v_res record;
  v_total numeric(18,4) := 0;
  v_released numeric(18,4);
BEGIN
  SELECT * INTO v_po FROM public.production_orders WHERE id = p_production_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order not found'; END IF;

  IF NOT public.has_company_role(v_po.company_id, ARRAY['ADMIN','WAREHOUSE','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_po.status IN ('FINISHED','CANCELLED') THEN
    RAISE EXCEPTION 'Cannot release reservations for finished/cancelled order';
  END IF;

  FOR v_res IN
    SELECT id
    FROM public.inventory_reservations
    WHERE production_order_id = p_production_order_id
      AND status IN ('ACTIVE','PARTIALLY_CONSUMED')
      AND reserved_qty > consumed_qty + released_qty
    ORDER BY created_at
  LOOP
    v_released := public.release_inventory_reservation(v_res.id, NULL);
    v_total := v_total + v_released;
  END LOOP;

  RETURN v_total;
END;
$$;
