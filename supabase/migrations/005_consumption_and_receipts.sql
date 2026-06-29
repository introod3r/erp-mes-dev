-- Production material consumption and finished goods receipt workflows.
-- Apply after 004_material_availability_and_reservation.sql

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
      AND reserved_qty > consumed_qty
    ORDER BY created_at
    FOR UPDATE
  LOOP
    EXIT WHEN v_remaining <= 0;
    v_take := LEAST(v_remaining, v_res.reserved_qty - v_res.consumed_qty);

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
          WHEN consumed_qty + v_take >= reserved_qty THEN 'CONSUMED'
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

CREATE OR REPLACE FUNCTION public.receive_finished_goods(
  p_production_order_id uuid,
  p_warehouse_id uuid,
  p_quantity_good numeric,
  p_quantity_scrap numeric DEFAULT 0,
  p_scrap_warehouse_id uuid DEFAULT NULL,
  p_lot_number text DEFAULT NULL,
  p_finish_order boolean DEFAULT false
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po public.production_orders%ROWTYPE;
  v_item public.items%ROWTYPE;
  v_lot_id uuid;
  v_tx_id uuid;
  v_good_line_id uuid;
  v_scrap_line_id uuid;
  v_receipt_line_id uuid;
  v_balance public.stock_balances%ROWTYPE;
BEGIN
  IF p_quantity_good < 0 OR p_quantity_scrap < 0 THEN
    RAISE EXCEPTION 'Receipt quantities cannot be negative';
  END IF;
  IF p_quantity_good = 0 AND p_quantity_scrap = 0 THEN
    RAISE EXCEPTION 'At least one receipt quantity must be positive';
  END IF;

  SELECT * INTO v_po FROM public.production_orders WHERE id = p_production_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order not found'; END IF;

  IF NOT public.has_company_role(v_po.company_id, ARRAY['ADMIN','WAREHOUSE','PRODUCTION_OPERATOR','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_po.status NOT IN ('RELEASED','IN_PROGRESS') THEN
    RAISE EXCEPTION 'Can receive finished goods only for RELEASED or IN_PROGRESS orders';
  END IF;

  SELECT * INTO v_item FROM public.items WHERE id = v_po.item_id AND company_id = v_po.company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production item not found'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.warehouses WHERE id = p_warehouse_id AND company_id = v_po.company_id) THEN
    RAISE EXCEPTION 'Receipt warehouse does not belong to company';
  END IF;

  IF p_quantity_scrap > 0 THEN
    IF p_scrap_warehouse_id IS NULL THEN RAISE EXCEPTION 'Scrap warehouse is required when scrap quantity is positive'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.warehouses WHERE id = p_scrap_warehouse_id AND company_id = v_po.company_id) THEN
      RAISE EXCEPTION 'Scrap warehouse does not belong to company';
    END IF;
  END IF;

  IF v_item.is_lot_tracked THEN
    IF trim(COALESCE(p_lot_number, '')) = '' THEN
      RAISE EXCEPTION 'Lot number is required for lot-tracked finished item';
    END IF;
    INSERT INTO public.lots(company_id, item_id, lot_number)
    VALUES(v_po.company_id, v_po.item_id, trim(p_lot_number))
    ON CONFLICT(company_id, item_id, lot_number) DO UPDATE SET lot_number = EXCLUDED.lot_number
    RETURNING id INTO v_lot_id;
  END IF;

  INSERT INTO public.inventory_transactions(
    company_id, transaction_type, source_type, source_id, reference_number, note, created_by
  ) VALUES (
    v_po.company_id, 'PRODUCTION_RECEIPT', 'PRODUCTION_ORDER', v_po.id, v_po.order_number,
    'Finished goods receipt from production order', auth.uid()
  ) RETURNING id INTO v_tx_id;

  IF p_quantity_good > 0 THEN
    v_balance := public.get_or_create_stock_balance(v_po.company_id, v_po.item_id, p_warehouse_id, NULL, v_lot_id);
    UPDATE public.stock_balances
    SET quantity_on_hand = quantity_on_hand + p_quantity_good,
        updated_at = now()
    WHERE id = v_balance.id;

    INSERT INTO public.inventory_transaction_lines(
      company_id, transaction_id, item_id, lot_id, to_warehouse_id, quantity, uom_id, production_order_id
    ) VALUES (
      v_po.company_id, v_tx_id, v_po.item_id, v_lot_id, p_warehouse_id, p_quantity_good, v_po.uom_id, v_po.id
    ) RETURNING id INTO v_good_line_id;
  END IF;

  IF p_quantity_scrap > 0 THEN
    v_balance := public.get_or_create_stock_balance(v_po.company_id, v_po.item_id, p_scrap_warehouse_id, NULL, v_lot_id);
    UPDATE public.stock_balances
    SET quantity_on_hand = quantity_on_hand + p_quantity_scrap,
        updated_at = now()
    WHERE id = v_balance.id;

    INSERT INTO public.inventory_transaction_lines(
      company_id, transaction_id, item_id, lot_id, to_warehouse_id, quantity, uom_id, production_order_id
    ) VALUES (
      v_po.company_id, v_tx_id, v_po.item_id, v_lot_id, p_scrap_warehouse_id, p_quantity_scrap, v_po.uom_id, v_po.id
    ) RETURNING id INTO v_scrap_line_id;
  END IF;

  v_receipt_line_id := COALESCE(v_good_line_id, v_scrap_line_id);

  INSERT INTO public.production_receipts(
    company_id, production_order_id, item_id, lot_id, warehouse_id, quantity_good, quantity_scrap,
    uom_id, inventory_transaction_line_id, received_by
  ) VALUES (
    v_po.company_id, v_po.id, v_po.item_id, v_lot_id, p_warehouse_id, p_quantity_good, p_quantity_scrap,
    v_po.uom_id, v_receipt_line_id, auth.uid()
  );

  UPDATE public.production_orders
  SET produced_quantity = produced_quantity + p_quantity_good,
      scrap_quantity = scrap_quantity + p_quantity_scrap,
      status = CASE
        WHEN p_finish_order OR produced_quantity + p_quantity_good >= planned_quantity THEN 'FINISHED'
        ELSE 'IN_PROGRESS'
      END,
      actual_start_date = COALESCE(actual_start_date, now()),
      actual_end_date = CASE
        WHEN p_finish_order OR produced_quantity + p_quantity_good >= planned_quantity THEN now()
        ELSE actual_end_date
      END,
      updated_at = now()
  WHERE id = v_po.id;

  RETURN v_tx_id;
END;
$$;
