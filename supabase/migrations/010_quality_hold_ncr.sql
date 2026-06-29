-- Basic quality hold / quarantine and nonconformance foundation.
-- Apply after 009_controlled_reversals.sql

CREATE TABLE IF NOT EXISTS public.nonconformance_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  ncr_number text NOT NULL,
  source_type text,
  source_id uuid,
  item_id uuid NULL REFERENCES public.items(id),
  lot_id uuid NULL REFERENCES public.lots(id),
  severity text NOT NULL CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')) DEFAULT 'MEDIUM',
  status text NOT NULL CHECK (status IN ('OPEN','UNDER_REVIEW','DISPOSITIONED','CLOSED','CANCELLED')) DEFAULT 'OPEN',
  description text NOT NULL,
  disposition text CHECK (disposition IN ('USE_AS_IS','REWORK','SCRAP','RETURN_TO_SUPPLIER','SORT','PENDING')) DEFAULT 'PENDING',
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz,
  UNIQUE(company_id, ncr_number)
);
CREATE INDEX IF NOT EXISTS idx_ncr_company_status ON public.nonconformance_reports(company_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ncr_item_lot ON public.nonconformance_reports(company_id, item_id, lot_id);

CREATE TABLE IF NOT EXISTS public.quality_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  hold_number text NOT NULL,
  ncr_id uuid NULL REFERENCES public.nonconformance_reports(id),
  item_id uuid NOT NULL REFERENCES public.items(id),
  lot_id uuid NULL REFERENCES public.lots(id),
  source_warehouse_id uuid NOT NULL REFERENCES public.warehouses(id),
  source_location_id uuid NULL REFERENCES public.warehouse_locations(id),
  hold_warehouse_id uuid NOT NULL REFERENCES public.warehouses(id),
  hold_location_id uuid NULL REFERENCES public.warehouse_locations(id),
  quantity numeric(18,4) NOT NULL CHECK(quantity > 0),
  remaining_qty numeric(18,4) NOT NULL CHECK(remaining_qty >= 0),
  uom_id uuid NOT NULL REFERENCES public.units_of_measure(id),
  reason_code text,
  note text,
  status text NOT NULL CHECK(status IN ('OPEN','PARTIALLY_RELEASED','RELEASED','PARTIALLY_SCRAPPED','SCRAPPED','CLOSED')) DEFAULT 'OPEN',
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  scrapped_at timestamptz,
  hold_transaction_id uuid REFERENCES public.inventory_transactions(id),
  UNIQUE(company_id, hold_number)
);
CREATE INDEX IF NOT EXISTS idx_quality_holds_company_status ON public.quality_holds(company_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_quality_holds_item_lot ON public.quality_holds(company_id, item_id, lot_id);

ALTER TABLE public.nonconformance_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.quality_holds ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ncr_member_select ON public.nonconformance_reports;
DROP POLICY IF EXISTS ncr_staff_insert ON public.nonconformance_reports;
DROP POLICY IF EXISTS ncr_staff_update ON public.nonconformance_reports;
CREATE POLICY ncr_member_select ON public.nonconformance_reports FOR SELECT USING (public.is_company_member(company_id));
CREATE POLICY ncr_staff_insert ON public.nonconformance_reports FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER','PLANNER','WAREHOUSE']));
CREATE POLICY ncr_staff_update ON public.nonconformance_reports FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER']));

DROP POLICY IF EXISTS quality_holds_member_select ON public.quality_holds;
DROP POLICY IF EXISTS quality_holds_staff_insert ON public.quality_holds;
DROP POLICY IF EXISTS quality_holds_staff_update ON public.quality_holds;
CREATE POLICY quality_holds_member_select ON public.quality_holds FOR SELECT USING (public.is_company_member(company_id));
CREATE POLICY quality_holds_staff_insert ON public.quality_holds FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER','PLANNER','WAREHOUSE']));
CREATE POLICY quality_holds_staff_update ON public.quality_holds FOR UPDATE USING (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER','WAREHOUSE'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN','QUALITY','MANAGER','WAREHOUSE']));

CREATE OR REPLACE FUNCTION public.create_nonconformance_report(
  p_company_id uuid,
  p_ncr_number text,
  p_description text,
  p_item_id uuid DEFAULT NULL,
  p_lot_id uuid DEFAULT NULL,
  p_source_type text DEFAULT NULL,
  p_source_id uuid DEFAULT NULL,
  p_severity text DEFAULT 'MEDIUM'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['ADMIN','QUALITY','MANAGER','PLANNER','WAREHOUSE']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF trim(COALESCE(p_ncr_number, '')) = '' THEN RAISE EXCEPTION 'NCR number is required'; END IF;
  IF trim(COALESCE(p_description, '')) = '' THEN RAISE EXCEPTION 'Description is required'; END IF;

  INSERT INTO public.nonconformance_reports(company_id, ncr_number, description, item_id, lot_id, source_type, source_id, severity, created_by)
  VALUES(p_company_id, trim(p_ncr_number), p_description, p_item_id, p_lot_id, p_source_type, p_source_id, p_severity, auth.uid())
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_quality_hold(
  p_company_id uuid,
  p_hold_number text,
  p_item_id uuid,
  p_source_warehouse_id uuid,
  p_hold_warehouse_id uuid,
  p_quantity numeric,
  p_lot_id uuid DEFAULT NULL,
  p_source_location_id uuid DEFAULT NULL,
  p_hold_location_id uuid DEFAULT NULL,
  p_ncr_id uuid DEFAULT NULL,
  p_reason_code text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_item public.items%ROWTYPE;
  v_src public.stock_balances%ROWTYPE;
  v_dst public.stock_balances%ROWTYPE;
  v_tx_id uuid;
  v_hold_id uuid;
BEGIN
  IF p_quantity <= 0 THEN RAISE EXCEPTION 'Hold quantity must be positive'; END IF;
  IF NOT public.has_company_role(p_company_id, ARRAY['ADMIN','QUALITY','MANAGER','WAREHOUSE']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF trim(COALESCE(p_hold_number, '')) = '' THEN RAISE EXCEPTION 'Hold number is required'; END IF;

  SELECT * INTO v_item FROM public.items WHERE id = p_item_id AND company_id = p_company_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Item not found'; END IF;
  IF v_item.is_lot_tracked AND p_lot_id IS NULL THEN RAISE EXCEPTION 'Lot is required for lot-tracked item'; END IF;

  IF NOT EXISTS (SELECT 1 FROM public.warehouses WHERE id = p_source_warehouse_id AND company_id = p_company_id) THEN
    RAISE EXCEPTION 'Source warehouse invalid';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.warehouses WHERE id = p_hold_warehouse_id AND company_id = p_company_id AND warehouse_type = 'QUALITY') THEN
    RAISE EXCEPTION 'Hold warehouse must be a QUALITY warehouse';
  END IF;

  SELECT * INTO v_src
  FROM public.stock_balances
  WHERE company_id = p_company_id
    AND item_id = p_item_id
    AND warehouse_id = p_source_warehouse_id
    AND location_id IS NOT DISTINCT FROM p_source_location_id
    AND lot_id IS NOT DISTINCT FROM p_lot_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'Source stock balance not found'; END IF;
  IF v_src.quantity_on_hand - v_src.quantity_reserved < p_quantity THEN
    RAISE EXCEPTION 'Insufficient available stock for quality hold';
  END IF;

  INSERT INTO public.inventory_transactions(company_id, transaction_type, source_type, source_id, reference_number, note, created_by)
  VALUES(p_company_id, 'TRANSFER', 'QUALITY_HOLD', NULL, p_hold_number, COALESCE(p_note, 'Quality hold transfer'), auth.uid())
  RETURNING id INTO v_tx_id;

  INSERT INTO public.inventory_transaction_lines(company_id, transaction_id, item_id, lot_id, from_warehouse_id, from_location_id, to_warehouse_id, to_location_id, quantity, uom_id)
  VALUES(p_company_id, v_tx_id, p_item_id, p_lot_id, p_source_warehouse_id, p_source_location_id, p_hold_warehouse_id, p_hold_location_id, p_quantity, v_item.default_uom_id);

  UPDATE public.stock_balances
  SET quantity_on_hand = quantity_on_hand - p_quantity, updated_at = now()
  WHERE id = v_src.id;

  v_dst := public.get_or_create_stock_balance(p_company_id, p_item_id, p_hold_warehouse_id, p_hold_location_id, p_lot_id);
  UPDATE public.stock_balances
  SET quantity_on_hand = quantity_on_hand + p_quantity, updated_at = now()
  WHERE id = v_dst.id;

  INSERT INTO public.quality_holds(
    company_id, hold_number, ncr_id, item_id, lot_id, source_warehouse_id, source_location_id,
    hold_warehouse_id, hold_location_id, quantity, remaining_qty, uom_id, reason_code, note, created_by, hold_transaction_id
  ) VALUES (
    p_company_id, trim(p_hold_number), p_ncr_id, p_item_id, p_lot_id, p_source_warehouse_id, p_source_location_id,
    p_hold_warehouse_id, p_hold_location_id, p_quantity, p_quantity, v_item.default_uom_id, p_reason_code, p_note, auth.uid(), v_tx_id
  ) RETURNING id INTO v_hold_id;

  UPDATE public.inventory_transactions SET source_id = v_hold_id WHERE id = v_tx_id;
  RETURN v_hold_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_quality_hold(
  p_quality_hold_id uuid,
  p_quantity numeric DEFAULT NULL,
  p_to_warehouse_id uuid DEFAULT NULL,
  p_to_location_id uuid DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hold public.quality_holds%ROWTYPE;
  v_src public.stock_balances%ROWTYPE;
  v_dst public.stock_balances%ROWTYPE;
  v_qty numeric(18,4);
  v_target_wh uuid;
  v_tx_id uuid;
BEGIN
  SELECT * INTO v_hold FROM public.quality_holds WHERE id = p_quality_hold_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Quality hold not found'; END IF;
  IF NOT public.has_company_role(v_hold.company_id, ARRAY['ADMIN','QUALITY','MANAGER','WAREHOUSE']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF v_hold.status IN ('RELEASED','SCRAPPED','CLOSED') OR v_hold.remaining_qty <= 0 THEN
    RAISE EXCEPTION 'Quality hold has no releasable quantity';
  END IF;

  v_qty := COALESCE(p_quantity, v_hold.remaining_qty);
  IF v_qty <= 0 OR v_qty > v_hold.remaining_qty THEN RAISE EXCEPTION 'Invalid release quantity'; END IF;
  v_target_wh := COALESCE(p_to_warehouse_id, v_hold.source_warehouse_id);

  SELECT * INTO v_src
  FROM public.stock_balances
  WHERE company_id = v_hold.company_id AND item_id = v_hold.item_id AND warehouse_id = v_hold.hold_warehouse_id
    AND location_id IS NOT DISTINCT FROM v_hold.hold_location_id AND lot_id IS NOT DISTINCT FROM v_hold.lot_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Hold stock balance not found'; END IF;
  IF v_src.quantity_on_hand - v_src.quantity_reserved < v_qty THEN RAISE EXCEPTION 'Hold stock is not available for release'; END IF;

  INSERT INTO public.inventory_transactions(company_id, transaction_type, source_type, source_id, reference_number, note, created_by)
  VALUES(v_hold.company_id, 'TRANSFER', 'QUALITY_HOLD_RELEASE', v_hold.id, v_hold.hold_number, COALESCE(p_note, 'Quality hold release'), auth.uid())
  RETURNING id INTO v_tx_id;

  INSERT INTO public.inventory_transaction_lines(company_id, transaction_id, item_id, lot_id, from_warehouse_id, from_location_id, to_warehouse_id, to_location_id, quantity, uom_id)
  VALUES(v_hold.company_id, v_tx_id, v_hold.item_id, v_hold.lot_id, v_hold.hold_warehouse_id, v_hold.hold_location_id, v_target_wh, COALESCE(p_to_location_id, v_hold.source_location_id), v_qty, v_hold.uom_id);

  UPDATE public.stock_balances SET quantity_on_hand = quantity_on_hand - v_qty, updated_at = now() WHERE id = v_src.id;
  v_dst := public.get_or_create_stock_balance(v_hold.company_id, v_hold.item_id, v_target_wh, COALESCE(p_to_location_id, v_hold.source_location_id), v_hold.lot_id);
  UPDATE public.stock_balances SET quantity_on_hand = quantity_on_hand + v_qty, updated_at = now() WHERE id = v_dst.id;

  UPDATE public.quality_holds
  SET remaining_qty = remaining_qty - v_qty,
      status = CASE WHEN remaining_qty - v_qty <= 0 THEN 'RELEASED' ELSE 'PARTIALLY_RELEASED' END,
      released_at = CASE WHEN remaining_qty - v_qty <= 0 THEN now() ELSE released_at END
  WHERE id = v_hold.id;

  RETURN v_tx_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.scrap_quality_hold(
  p_quality_hold_id uuid,
  p_scrap_warehouse_id uuid,
  p_quantity numeric DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hold public.quality_holds%ROWTYPE;
  v_src public.stock_balances%ROWTYPE;
  v_dst public.stock_balances%ROWTYPE;
  v_qty numeric(18,4);
  v_tx_id uuid;
BEGIN
  SELECT * INTO v_hold FROM public.quality_holds WHERE id = p_quality_hold_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Quality hold not found'; END IF;
  IF NOT public.has_company_role(v_hold.company_id, ARRAY['ADMIN','QUALITY','MANAGER','WAREHOUSE']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF v_hold.status IN ('RELEASED','SCRAPPED','CLOSED') OR v_hold.remaining_qty <= 0 THEN
    RAISE EXCEPTION 'Quality hold has no scrappable quantity';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.warehouses WHERE id = p_scrap_warehouse_id AND company_id = v_hold.company_id AND warehouse_type = 'SCRAP') THEN
    RAISE EXCEPTION 'Scrap warehouse must be a SCRAP warehouse';
  END IF;

  v_qty := COALESCE(p_quantity, v_hold.remaining_qty);
  IF v_qty <= 0 OR v_qty > v_hold.remaining_qty THEN RAISE EXCEPTION 'Invalid scrap quantity'; END IF;

  SELECT * INTO v_src
  FROM public.stock_balances
  WHERE company_id = v_hold.company_id AND item_id = v_hold.item_id AND warehouse_id = v_hold.hold_warehouse_id
    AND location_id IS NOT DISTINCT FROM v_hold.hold_location_id AND lot_id IS NOT DISTINCT FROM v_hold.lot_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Hold stock balance not found'; END IF;
  IF v_src.quantity_on_hand - v_src.quantity_reserved < v_qty THEN RAISE EXCEPTION 'Hold stock is not available for scrap'; END IF;

  INSERT INTO public.inventory_transactions(company_id, transaction_type, source_type, source_id, reference_number, note, created_by)
  VALUES(v_hold.company_id, 'SCRAP', 'QUALITY_HOLD_SCRAP', v_hold.id, v_hold.hold_number, COALESCE(p_note, 'Quality hold scrap disposition'), auth.uid())
  RETURNING id INTO v_tx_id;

  INSERT INTO public.inventory_transaction_lines(company_id, transaction_id, item_id, lot_id, from_warehouse_id, from_location_id, to_warehouse_id, quantity, uom_id)
  VALUES(v_hold.company_id, v_tx_id, v_hold.item_id, v_hold.lot_id, v_hold.hold_warehouse_id, v_hold.hold_location_id, p_scrap_warehouse_id, v_qty, v_hold.uom_id);

  UPDATE public.stock_balances SET quantity_on_hand = quantity_on_hand - v_qty, updated_at = now() WHERE id = v_src.id;
  v_dst := public.get_or_create_stock_balance(v_hold.company_id, v_hold.item_id, p_scrap_warehouse_id, NULL, v_hold.lot_id);
  UPDATE public.stock_balances SET quantity_on_hand = quantity_on_hand + v_qty, updated_at = now() WHERE id = v_dst.id;

  UPDATE public.quality_holds
  SET remaining_qty = remaining_qty - v_qty,
      status = CASE WHEN remaining_qty - v_qty <= 0 THEN 'SCRAPPED' ELSE 'PARTIALLY_SCRAPPED' END,
      scrapped_at = CASE WHEN remaining_qty - v_qty <= 0 THEN now() ELSE scrapped_at END
  WHERE id = v_hold.id;

  IF v_hold.ncr_id IS NOT NULL THEN
    UPDATE public.nonconformance_reports
    SET disposition = 'SCRAP', status = CASE WHEN status = 'OPEN' THEN 'DISPOSITIONED' ELSE status END
    WHERE id = v_hold.ncr_id;
  END IF;

  RETURN v_tx_id;
END;
$$;
