-- Controlled reversal/correction workflows.
-- Apply after 008_reservation_release.sql

ALTER TABLE public.inventory_transactions DROP CONSTRAINT IF EXISTS inventory_transactions_transaction_type_check;
ALTER TABLE public.inventory_transactions ADD CONSTRAINT inventory_transactions_transaction_type_check CHECK (
  transaction_type IN (
    'PURCHASE_RECEIPT','PRODUCTION_ISSUE','PRODUCTION_RECEIPT','TRANSFER','ADJUSTMENT_IN','ADJUSTMENT_OUT','SCRAP','SALES_SHIPMENT','RETURN','REVERSAL'
  )
);

ALTER TABLE public.production_consumptions
ADD COLUMN IF NOT EXISTS reservation_id uuid NULL REFERENCES public.inventory_reservations(id),
ADD COLUMN IF NOT EXISTS is_reversed boolean NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS reversed_at timestamptz,
ADD COLUMN IF NOT EXISTS reversed_by uuid REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS reversal_transaction_id uuid REFERENCES public.inventory_transactions(id);

ALTER TABLE public.production_receipts
ADD COLUMN IF NOT EXISTS is_reversed boolean NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS reversed_at timestamptz,
ADD COLUMN IF NOT EXISTS reversed_by uuid REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS reversal_transaction_id uuid REFERENCES public.inventory_transactions(id);

ALTER TABLE public.production_operation_events
ADD COLUMN IF NOT EXISTS is_reversed boolean NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS reversed_at timestamptz,
ADD COLUMN IF NOT EXISTS reversed_by uuid REFERENCES auth.users(id),
ADD COLUMN IF NOT EXISTS reversal_note text;

-- Update future consumption postings to store reservation_id for accurate reversal.
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
  IF p_qty <= 0 THEN RAISE EXCEPTION 'Consumption quantity must be positive'; END IF;

  SELECT * INTO v_pom FROM public.production_order_materials WHERE id = p_production_order_material_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order material not found'; END IF;

  SELECT * INTO v_po FROM public.production_orders WHERE id = v_pom.production_order_id FOR UPDATE;

  IF NOT public.has_company_role(v_pom.company_id, ARRAY['ADMIN','WAREHOUSE','PRODUCTION_OPERATOR','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_po.status NOT IN ('RELEASED','IN_PROGRESS') THEN
    RAISE EXCEPTION 'Can consume materials only for RELEASED or IN_PROGRESS orders';
  END IF;

  IF p_qty > (v_pom.reserved_qty - v_pom.consumed_qty) THEN
    RAISE EXCEPTION 'Consumption quantity exceeds remaining reserved quantity. Reserve material first.';
  END IF;

  INSERT INTO public.inventory_transactions(company_id, transaction_type, source_type, source_id, reference_number, note, created_by)
  VALUES (v_pom.company_id, 'PRODUCTION_ISSUE', 'PRODUCTION_ORDER', v_po.id, v_po.order_number, 'Material consumption for production order', auth.uid())
  RETURNING id INTO v_tx_id;

  v_remaining := p_qty;

  FOR v_res IN
    SELECT * FROM public.inventory_reservations
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
      company_id, transaction_id, item_id, lot_id, from_warehouse_id, from_location_id, quantity, uom_id,
      production_order_id, production_order_material_id
    ) VALUES (
      v_pom.company_id, v_tx_id, v_pom.item_id, v_res.lot_id, v_res.warehouse_id, v_res.location_id, v_take, v_pom.uom_id,
      v_po.id, v_pom.id
    ) RETURNING id INTO v_line_id;

    INSERT INTO public.production_consumptions(
      company_id, production_order_id, production_order_material_id, reservation_id, item_id, lot_id,
      warehouse_id, location_id, quantity, uom_id, inventory_transaction_line_id, consumed_by
    ) VALUES (
      v_pom.company_id, v_po.id, v_pom.id, v_res.id, v_pom.item_id, v_res.lot_id,
      v_res.warehouse_id, v_res.location_id, v_take, v_pom.uom_id, v_line_id, auth.uid()
    );

    UPDATE public.inventory_reservations
    SET consumed_qty = consumed_qty + v_take,
        status = CASE WHEN consumed_qty + v_take + released_qty >= reserved_qty THEN 'CONSUMED' ELSE 'PARTIALLY_CONSUMED' END
    WHERE id = v_res.id;

    v_remaining := v_remaining - v_take;
  END LOOP;

  IF v_remaining > 0 THEN RAISE EXCEPTION 'Reserved material disappeared during consumption'; END IF;

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

CREATE OR REPLACE FUNCTION public.reverse_inventory_transaction(
  p_transaction_id uuid,
  p_note text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tx public.inventory_transactions%ROWTYPE;
  v_line public.inventory_transaction_lines%ROWTYPE;
  v_rev_tx_id uuid;
  v_bal public.stock_balances%ROWTYPE;
BEGIN
  SELECT * INTO v_tx FROM public.inventory_transactions WHERE id = p_transaction_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Inventory transaction not found'; END IF;

  IF NOT public.has_company_role(v_tx.company_id, ARRAY['ADMIN','WAREHOUSE','MANAGER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_tx.is_reversed THEN RAISE EXCEPTION 'Transaction is already reversed'; END IF;
  IF v_tx.transaction_type IN ('PRODUCTION_ISSUE','PRODUCTION_RECEIPT') THEN
    RAISE EXCEPTION 'Use production-specific reversal for production transactions';
  END IF;

  INSERT INTO public.inventory_transactions(company_id, transaction_type, source_type, source_id, reference_number, note, created_by, reversed_transaction_id)
  VALUES(v_tx.company_id, 'REVERSAL', 'INVENTORY_TRANSACTION', v_tx.id, v_tx.reference_number, COALESCE(p_note, 'Inventory transaction reversal'), auth.uid(), v_tx.id)
  RETURNING id INTO v_rev_tx_id;

  FOR v_line IN SELECT * FROM public.inventory_transaction_lines WHERE transaction_id = v_tx.id ORDER BY created_at FOR UPDATE LOOP
    IF v_line.to_warehouse_id IS NOT NULL THEN
      v_bal := public.get_or_create_stock_balance(v_tx.company_id, v_line.item_id, v_line.to_warehouse_id, v_line.to_location_id, v_line.lot_id);
      IF v_bal.quantity_on_hand - v_bal.quantity_reserved < v_line.quantity THEN
        RAISE EXCEPTION 'Cannot reverse transaction: insufficient available stock for item %', v_line.item_id;
      END IF;
      UPDATE public.stock_balances SET quantity_on_hand = quantity_on_hand - v_line.quantity, updated_at = now() WHERE id = v_bal.id;
    END IF;

    IF v_line.from_warehouse_id IS NOT NULL THEN
      v_bal := public.get_or_create_stock_balance(v_tx.company_id, v_line.item_id, v_line.from_warehouse_id, v_line.from_location_id, v_line.lot_id);
      UPDATE public.stock_balances SET quantity_on_hand = quantity_on_hand + v_line.quantity, updated_at = now() WHERE id = v_bal.id;
    END IF;

    INSERT INTO public.inventory_transaction_lines(
      company_id, transaction_id, item_id, lot_id,
      from_warehouse_id, from_location_id, to_warehouse_id, to_location_id,
      quantity, uom_id, unit_cost, total_cost, production_order_id, production_order_material_id
    ) VALUES (
      v_tx.company_id, v_rev_tx_id, v_line.item_id, v_line.lot_id,
      v_line.to_warehouse_id, v_line.to_location_id, v_line.from_warehouse_id, v_line.from_location_id,
      v_line.quantity, v_line.uom_id, v_line.unit_cost, v_line.total_cost, v_line.production_order_id, v_line.production_order_material_id
    );
  END LOOP;

  UPDATE public.inventory_transactions SET is_reversed = true WHERE id = v_tx.id;
  RETURN v_rev_tx_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reverse_production_consumption(
  p_consumption_id uuid,
  p_note text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cons public.production_consumptions%ROWTYPE;
  v_pom public.production_order_materials%ROWTYPE;
  v_po public.production_orders%ROWTYPE;
  v_res public.inventory_reservations%ROWTYPE;
  v_bal public.stock_balances%ROWTYPE;
  v_tx_id uuid;
  v_line_id uuid;
BEGIN
  SELECT * INTO v_cons FROM public.production_consumptions WHERE id = p_consumption_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production consumption not found'; END IF;
  IF v_cons.is_reversed THEN RAISE EXCEPTION 'Production consumption already reversed'; END IF;
  IF v_cons.reservation_id IS NULL THEN RAISE EXCEPTION 'Cannot reverse old consumption without reservation link'; END IF;

  SELECT * INTO v_pom FROM public.production_order_materials WHERE id = v_cons.production_order_material_id FOR UPDATE;
  SELECT * INTO v_po FROM public.production_orders WHERE id = v_cons.production_order_id FOR UPDATE;
  SELECT * INTO v_res FROM public.inventory_reservations WHERE id = v_cons.reservation_id FOR UPDATE;

  IF NOT public.has_company_role(v_cons.company_id, ARRAY['ADMIN','WAREHOUSE','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF v_po.status = 'FINISHED' THEN RAISE EXCEPTION 'Cannot reverse consumption on FINISHED order'; END IF;
  IF v_res.consumed_qty < v_cons.quantity THEN RAISE EXCEPTION 'Reservation consumed quantity inconsistency'; END IF;

  INSERT INTO public.inventory_transactions(company_id, transaction_type, source_type, source_id, reference_number, note, created_by)
  VALUES(v_cons.company_id, 'REVERSAL', 'PRODUCTION_CONSUMPTION', v_cons.id, v_po.order_number, COALESCE(p_note, 'Production consumption reversal'), auth.uid())
  RETURNING id INTO v_tx_id;

  v_bal := public.get_or_create_stock_balance(v_cons.company_id, v_cons.item_id, v_cons.warehouse_id, v_cons.location_id, v_cons.lot_id);
  UPDATE public.stock_balances
  SET quantity_on_hand = quantity_on_hand + v_cons.quantity,
      quantity_reserved = quantity_reserved + v_cons.quantity,
      updated_at = now()
  WHERE id = v_bal.id;

  INSERT INTO public.inventory_transaction_lines(company_id, transaction_id, item_id, lot_id, to_warehouse_id, to_location_id, quantity, uom_id, production_order_id, production_order_material_id)
  VALUES(v_cons.company_id, v_tx_id, v_cons.item_id, v_cons.lot_id, v_cons.warehouse_id, v_cons.location_id, v_cons.quantity, v_cons.uom_id, v_cons.production_order_id, v_cons.production_order_material_id)
  RETURNING id INTO v_line_id;

  UPDATE public.inventory_reservations
  SET consumed_qty = consumed_qty - v_cons.quantity,
      status = CASE
        WHEN consumed_qty - v_cons.quantity <= 0 THEN 'ACTIVE'
        ELSE 'PARTIALLY_CONSUMED'
      END
  WHERE id = v_res.id;

  UPDATE public.production_order_materials
  SET consumed_qty = consumed_qty - v_cons.quantity,
      issued_qty = issued_qty - v_cons.quantity
  WHERE id = v_pom.id;

  UPDATE public.production_consumptions
  SET is_reversed = true, reversed_at = now(), reversed_by = auth.uid(), reversal_transaction_id = v_tx_id
  WHERE id = v_cons.id;

  RETURN v_tx_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reverse_production_receipt(
  p_receipt_id uuid,
  p_note text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_receipt public.production_receipts%ROWTYPE;
  v_po public.production_orders%ROWTYPE;
  v_orig_line public.inventory_transaction_lines%ROWTYPE;
  v_line public.inventory_transaction_lines%ROWTYPE;
  v_bal public.stock_balances%ROWTYPE;
  v_rev_tx_id uuid;
BEGIN
  SELECT * INTO v_receipt FROM public.production_receipts WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production receipt not found'; END IF;
  IF v_receipt.is_reversed THEN RAISE EXCEPTION 'Production receipt already reversed'; END IF;

  SELECT * INTO v_po FROM public.production_orders WHERE id = v_receipt.production_order_id FOR UPDATE;

  IF NOT public.has_company_role(v_receipt.company_id, ARRAY['ADMIN','WAREHOUSE','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_orig_line FROM public.inventory_transaction_lines WHERE id = v_receipt.inventory_transaction_line_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Original receipt inventory line not found'; END IF;

  INSERT INTO public.inventory_transactions(company_id, transaction_type, source_type, source_id, reference_number, note, created_by, reversed_transaction_id)
  VALUES(v_receipt.company_id, 'REVERSAL', 'PRODUCTION_RECEIPT', v_receipt.id, v_po.order_number, COALESCE(p_note, 'Production receipt reversal'), auth.uid(), v_orig_line.transaction_id)
  RETURNING id INTO v_rev_tx_id;

  FOR v_line IN SELECT * FROM public.inventory_transaction_lines WHERE transaction_id = v_orig_line.transaction_id ORDER BY created_at FOR UPDATE LOOP
    IF v_line.to_warehouse_id IS NULL THEN CONTINUE; END IF;

    v_bal := public.get_or_create_stock_balance(v_receipt.company_id, v_line.item_id, v_line.to_warehouse_id, v_line.to_location_id, v_line.lot_id);
    IF v_bal.quantity_on_hand - v_bal.quantity_reserved < v_line.quantity THEN
      RAISE EXCEPTION 'Cannot reverse receipt: stock already used/reserved for item %', v_line.item_id;
    END IF;

    UPDATE public.stock_balances SET quantity_on_hand = quantity_on_hand - v_line.quantity, updated_at = now() WHERE id = v_bal.id;

    INSERT INTO public.inventory_transaction_lines(company_id, transaction_id, item_id, lot_id, from_warehouse_id, from_location_id, quantity, uom_id, production_order_id)
    VALUES(v_receipt.company_id, v_rev_tx_id, v_line.item_id, v_line.lot_id, v_line.to_warehouse_id, v_line.to_location_id, v_line.quantity, v_line.uom_id, v_line.production_order_id);
  END LOOP;

  UPDATE public.production_orders
  SET produced_quantity = produced_quantity - v_receipt.quantity_good,
      scrap_quantity = scrap_quantity - v_receipt.quantity_scrap,
      status = CASE WHEN status = 'FINISHED' THEN 'IN_PROGRESS' ELSE status END,
      actual_end_date = CASE WHEN status = 'FINISHED' THEN NULL ELSE actual_end_date END,
      updated_at = now()
  WHERE id = v_po.id;

  UPDATE public.production_receipts
  SET is_reversed = true, reversed_at = now(), reversed_by = auth.uid(), reversal_transaction_id = v_rev_tx_id
  WHERE id = v_receipt.id;

  UPDATE public.inventory_transactions SET is_reversed = true WHERE id = v_orig_line.transaction_id;
  RETURN v_rev_tx_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reverse_operation_event(
  p_event_id uuid,
  p_note text DEFAULT NULL
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_event public.production_operation_events%ROWTYPE;
  v_op public.production_order_operations%ROWTYPE;
BEGIN
  SELECT * INTO v_event FROM public.production_operation_events WHERE id = p_event_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Operation event not found'; END IF;
  IF v_event.is_reversed THEN RAISE EXCEPTION 'Operation event already reversed'; END IF;

  SELECT * INTO v_op FROM public.production_order_operations WHERE id = v_event.production_order_operation_id FOR UPDATE;

  IF NOT public.has_company_role(v_event.company_id, ARRAY['ADMIN','PLANNER','MANAGER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_event.event_type NOT IN ('REPORT_QTY','REPORT_SCRAP','COMPLETE') THEN
    RAISE EXCEPTION 'Only quantity/report/complete events can be reversed by this function';
  END IF;

  UPDATE public.production_order_operations
  SET completed_quantity = GREATEST(completed_quantity - v_event.quantity_good, 0),
      scrap_quantity = GREATEST(scrap_quantity - v_event.quantity_scrap, 0),
      status = CASE WHEN v_event.event_type = 'COMPLETE' THEN 'READY' ELSE status END,
      completed_at = CASE WHEN v_event.event_type = 'COMPLETE' THEN NULL ELSE completed_at END
  WHERE id = v_op.id;

  UPDATE public.production_operation_events
  SET is_reversed = true, reversed_at = now(), reversed_by = auth.uid(), reversal_note = p_note
  WHERE id = v_event.id;
END;
$$;
