-- Metal Furniture Fittings ERP/MES Starter Schema
-- Target: Supabase PostgreSQL 15+
-- Apply with: supabase db push

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------- helpers ----------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ---------- tenancy/auth ----------
CREATE TABLE public.companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.company_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('ADMIN','PLANNER','WAREHOUSE','PRODUCTION_OPERATOR','QUALITY','MANAGER','READ_ONLY')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, user_id)
);
CREATE INDEX idx_company_memberships_user ON public.company_memberships(user_id, is_active);

CREATE OR REPLACE FUNCTION public.current_company_ids()
RETURNS uuid[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(array_agg(company_id), ARRAY[]::uuid[])
  FROM public.company_memberships
  WHERE user_id = auth.uid() AND is_active = true;
$$;

CREATE OR REPLACE FUNCTION public.is_company_member(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.company_memberships
    WHERE company_id = p_company_id AND user_id = auth.uid() AND is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION public.has_company_role(p_company_id uuid, p_roles text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.company_memberships
    WHERE company_id = p_company_id
      AND user_id = auth.uid()
      AND is_active = true
      AND role = ANY(p_roles)
  );
$$;


-- ---------- master data ----------
CREATE TABLE public.units_of_measure (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  code text NOT NULL,
  name text NOT NULL,
  symbol text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, code)
);

CREATE TABLE public.items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  item_code text NOT NULL,
  item_type text NOT NULL CHECK (item_type IN ('RAW_MATERIAL','SEMI_FINISHED','FINISHED_GOOD','CONSUMABLE','SERVICE')),
  default_uom_id uuid NOT NULL REFERENCES public.units_of_measure(id),
  name text NOT NULL,
  description text,
  is_stocked boolean NOT NULL DEFAULT true,
  is_purchased boolean NOT NULL DEFAULT false,
  is_manufactured boolean NOT NULL DEFAULT false,
  is_sellable boolean NOT NULL DEFAULT false,
  min_stock_qty numeric(18,4) NOT NULL DEFAULT 0,
  reorder_qty numeric(18,4) NOT NULL DEFAULT 0,
  is_lot_tracked boolean NOT NULL DEFAULT false,
  is_serial_tracked boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, item_code)
);
CREATE TRIGGER trg_items_updated_at BEFORE UPDATE ON public.items FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_items_company_type ON public.items(company_id, item_type);
CREATE INDEX idx_items_company_active ON public.items(company_id, is_active);

CREATE TABLE public.item_translations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id uuid NOT NULL REFERENCES public.items(id) ON DELETE CASCADE,
  language_code text NOT NULL CHECK (language_code IN ('en','sr','sr-Latn','sr-Cyrl')),
  name text NOT NULL,
  description text,
  UNIQUE(item_id, language_code)
);

CREATE TABLE public.unit_conversions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  item_id uuid NULL REFERENCES public.items(id),
  from_uom_id uuid NOT NULL REFERENCES public.units_of_measure(id),
  to_uom_id uuid NOT NULL REFERENCES public.units_of_measure(id),
  factor numeric(18,8) NOT NULL CHECK (factor > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE NULLS NOT DISTINCT(company_id, item_id, from_uom_id, to_uom_id)
);

CREATE TABLE public.warehouses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  code text NOT NULL,
  name text NOT NULL,
  warehouse_type text NOT NULL CHECK (warehouse_type IN ('RAW_MATERIAL','WIP','FINISHED_GOODS','SCRAP','QUALITY','GENERAL','SUBCONTRACTOR')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, code)
);

CREATE TABLE public.warehouse_locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  warehouse_id uuid NOT NULL REFERENCES public.warehouses(id),
  code text NOT NULL,
  name text,
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE(warehouse_id, code)
);
CREATE INDEX idx_locations_wh ON public.warehouse_locations(company_id, warehouse_id);

CREATE TABLE public.lots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  item_id uuid NOT NULL REFERENCES public.items(id),
  lot_number text NOT NULL,
  supplier_lot_number text,
  manufacturing_date date,
  expiration_date date,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, item_id, lot_number)
);
CREATE INDEX idx_lots_item ON public.lots(company_id, item_id);

-- ---------- BOM/routing ----------
CREATE TABLE public.boms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  parent_item_id uuid NOT NULL REFERENCES public.items(id),
  bom_code text NOT NULL,
  version text NOT NULL,
  status text NOT NULL CHECK (status IN ('DRAFT','ACTIVE','OBSOLETE')),
  valid_from date NOT NULL,
  valid_to date,
  output_quantity numeric(18,4) NOT NULL DEFAULT 1 CHECK(output_quantity > 0),
  output_uom_id uuid NOT NULL REFERENCES public.units_of_measure(id),
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, bom_code, version)
);
CREATE INDEX idx_boms_parent_active ON public.boms(company_id, parent_item_id, status, is_default);

CREATE TABLE public.bom_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  bom_id uuid NOT NULL REFERENCES public.boms(id) ON DELETE CASCADE,
  component_item_id uuid NOT NULL REFERENCES public.items(id),
  quantity_per numeric(18,6) NOT NULL CHECK(quantity_per > 0),
  uom_id uuid NOT NULL REFERENCES public.units_of_measure(id),
  scrap_factor_percent numeric(9,4) NOT NULL DEFAULT 0 CHECK(scrap_factor_percent >= 0),
  issue_method text NOT NULL CHECK(issue_method IN ('MANUAL','BACKFLUSH')),
  operation_sequence integer,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_bom_lines_bom ON public.bom_lines(bom_id);
CREATE INDEX idx_bom_lines_component ON public.bom_lines(company_id, component_item_id);

CREATE TABLE public.work_centers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  code text NOT NULL,
  name text NOT NULL,
  department text,
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE(company_id, code)
);

CREATE TABLE public.machines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  work_center_id uuid NOT NULL REFERENCES public.work_centers(id),
  code text NOT NULL,
  name text NOT NULL,
  machine_type text,
  status text NOT NULL CHECK(status IN ('AVAILABLE','RUNNING','DOWN','MAINTENANCE','INACTIVE')) DEFAULT 'AVAILABLE',
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE(company_id, code)
);
CREATE INDEX idx_machines_wc_status ON public.machines(company_id, work_center_id, status);

CREATE TABLE public.routings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  item_id uuid NOT NULL REFERENCES public.items(id),
  routing_code text NOT NULL,
  version text NOT NULL,
  status text NOT NULL CHECK(status IN ('DRAFT','ACTIVE','OBSOLETE')),
  valid_from date NOT NULL,
  valid_to date,
  is_default boolean NOT NULL DEFAULT false,
  UNIQUE(company_id, routing_code, version)
);

CREATE TABLE public.routing_operations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  routing_id uuid NOT NULL REFERENCES public.routings(id) ON DELETE CASCADE,
  sequence_no integer NOT NULL,
  operation_code text NOT NULL,
  operation_name text NOT NULL,
  work_center_id uuid NOT NULL REFERENCES public.work_centers(id),
  setup_time_minutes numeric(18,4) NOT NULL DEFAULT 0,
  run_time_minutes_per_unit numeric(18,6) NOT NULL DEFAULT 0,
  labor_required boolean NOT NULL DEFAULT true,
  machine_required boolean NOT NULL DEFAULT true,
  UNIQUE(routing_id, sequence_no)
);

-- ---------- production ----------
CREATE TABLE public.production_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  order_number text NOT NULL,
  item_id uuid NOT NULL REFERENCES public.items(id),
  bom_id uuid NULL REFERENCES public.boms(id),
  routing_id uuid NULL REFERENCES public.routings(id),
  planned_quantity numeric(18,4) NOT NULL CHECK(planned_quantity > 0),
  produced_quantity numeric(18,4) NOT NULL DEFAULT 0,
  scrap_quantity numeric(18,4) NOT NULL DEFAULT 0,
  uom_id uuid NOT NULL REFERENCES public.units_of_measure(id),
  status text NOT NULL CHECK(status IN ('PLANNED','RELEASED','IN_PROGRESS','FINISHED','CANCELLED','ON_HOLD')) DEFAULT 'PLANNED',
  planned_start_date timestamptz,
  planned_end_date timestamptz,
  actual_start_date timestamptz,
  actual_end_date timestamptz,
  priority integer NOT NULL DEFAULT 100,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, order_number)
);
CREATE TRIGGER trg_production_orders_updated_at BEFORE UPDATE ON public.production_orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE INDEX idx_po_status ON public.production_orders(company_id, status);
CREATE INDEX idx_po_item ON public.production_orders(company_id, item_id);
CREATE INDEX idx_po_dates ON public.production_orders(company_id, planned_start_date, planned_end_date);
CREATE INDEX idx_po_created ON public.production_orders(company_id, created_at DESC);

CREATE TABLE public.production_order_materials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  production_order_id uuid NOT NULL REFERENCES public.production_orders(id) ON DELETE CASCADE,
  item_id uuid NOT NULL REFERENCES public.items(id),
  planned_qty numeric(18,4) NOT NULL CHECK(planned_qty >= 0),
  reserved_qty numeric(18,4) NOT NULL DEFAULT 0,
  issued_qty numeric(18,4) NOT NULL DEFAULT 0,
  consumed_qty numeric(18,4) NOT NULL DEFAULT 0,
  uom_id uuid NOT NULL REFERENCES public.units_of_measure(id),
  source_bom_line_id uuid NULL REFERENCES public.bom_lines(id),
  issue_method text NOT NULL CHECK(issue_method IN ('MANUAL','BACKFLUSH')),
  operation_sequence integer,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_pom_order ON public.production_order_materials(production_order_id);
CREATE INDEX idx_pom_item ON public.production_order_materials(company_id, item_id);

CREATE TABLE public.production_order_operations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  production_order_id uuid NOT NULL REFERENCES public.production_orders(id) ON DELETE CASCADE,
  sequence_no integer NOT NULL,
  operation_code text NOT NULL,
  operation_name text NOT NULL,
  work_center_id uuid NOT NULL REFERENCES public.work_centers(id),
  machine_id uuid NULL REFERENCES public.machines(id),
  planned_setup_time_minutes numeric(18,4) NOT NULL DEFAULT 0,
  planned_run_time_minutes numeric(18,4) NOT NULL DEFAULT 0,
  actual_setup_time_minutes numeric(18,4) NOT NULL DEFAULT 0,
  actual_run_time_minutes numeric(18,4) NOT NULL DEFAULT 0,
  planned_quantity numeric(18,4) NOT NULL,
  completed_quantity numeric(18,4) NOT NULL DEFAULT 0,
  scrap_quantity numeric(18,4) NOT NULL DEFAULT 0,
  status text NOT NULL CHECK(status IN ('PENDING','READY','IN_PROGRESS','PAUSED','COMPLETED','SKIPPED','CANCELLED')) DEFAULT 'PENDING',
  started_at timestamptz,
  completed_at timestamptz,
  UNIQUE(production_order_id, sequence_no)
);
CREATE INDEX idx_poo_order ON public.production_order_operations(production_order_id);
CREATE INDEX idx_poo_wc ON public.production_order_operations(company_id, work_center_id, status);
CREATE INDEX idx_poo_machine ON public.production_order_operations(company_id, machine_id, status);

CREATE TABLE public.production_operation_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  production_order_operation_id uuid NOT NULL REFERENCES public.production_order_operations(id),
  event_type text NOT NULL CHECK(event_type IN ('START','STOP','PAUSE','RESUME','COMPLETE','REPORT_QTY','REPORT_SCRAP')),
  event_time timestamptz NOT NULL DEFAULT now(),
  operator_id uuid NULL REFERENCES auth.users(id),
  machine_id uuid NULL REFERENCES public.machines(id),
  quantity_good numeric(18,4) NOT NULL DEFAULT 0,
  quantity_scrap numeric(18,4) NOT NULL DEFAULT 0,
  reason_code text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_poe_operation_time ON public.production_operation_events(production_order_operation_id, event_time DESC);
CREATE INDEX idx_poe_machine_time ON public.production_operation_events(company_id, machine_id, event_time DESC);


-- Release production order: snapshots current BOM/routing into order-specific rows.
-- This starter implements a single-level BOM snapshot. Multi-level explosion should be added as a dedicated recursive RPC.
CREATE OR REPLACE FUNCTION public.release_production_order(p_production_order_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_po public.production_orders%ROWTYPE;
  v_bom_id uuid;
  v_routing_id uuid;
BEGIN
  SELECT * INTO v_po FROM public.production_orders WHERE id = p_production_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order not found'; END IF;
  IF NOT public.has_company_role(v_po.company_id, ARRAY['ADMIN','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF v_po.status <> 'PLANNED' THEN RAISE EXCEPTION 'Only PLANNED orders can be released'; END IF;

  v_bom_id := v_po.bom_id;
  IF v_bom_id IS NULL THEN
    SELECT id INTO v_bom_id
    FROM public.boms
    WHERE company_id = v_po.company_id
      AND parent_item_id = v_po.item_id
      AND status = 'ACTIVE'
      AND is_default = true
      AND valid_from <= CURRENT_DATE
      AND (valid_to IS NULL OR valid_to >= CURRENT_DATE)
    ORDER BY valid_from DESC
    LIMIT 1;
  END IF;
  IF v_bom_id IS NULL THEN RAISE EXCEPTION 'No active default BOM found'; END IF;

  v_routing_id := v_po.routing_id;
  IF v_routing_id IS NULL THEN
    SELECT id INTO v_routing_id
    FROM public.routings
    WHERE company_id = v_po.company_id
      AND item_id = v_po.item_id
      AND status = 'ACTIVE'
      AND is_default = true
      AND valid_from <= CURRENT_DATE
      AND (valid_to IS NULL OR valid_to >= CURRENT_DATE)
    ORDER BY valid_from DESC
    LIMIT 1;
  END IF;

  INSERT INTO public.production_order_materials(
    company_id, production_order_id, item_id, planned_qty, uom_id, source_bom_line_id, issue_method, operation_sequence
  )
  SELECT
    v_po.company_id,
    v_po.id,
    bl.component_item_id,
    ROUND((v_po.planned_quantity / b.output_quantity) * bl.quantity_per * (1 + bl.scrap_factor_percent / 100.0), 4),
    bl.uom_id,
    bl.id,
    bl.issue_method,
    bl.operation_sequence
  FROM public.boms b
  JOIN public.bom_lines bl ON bl.bom_id = b.id
  WHERE b.id = v_bom_id;

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

-- ---------- inventory ----------
CREATE TABLE public.inventory_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  transaction_type text NOT NULL CHECK(transaction_type IN ('PURCHASE_RECEIPT','PRODUCTION_ISSUE','PRODUCTION_RECEIPT','TRANSFER','ADJUSTMENT_IN','ADJUSTMENT_OUT','SCRAP','SALES_SHIPMENT','RETURN')),
  transaction_date timestamptz NOT NULL DEFAULT now(),
  source_type text,
  source_id uuid,
  reference_number text,
  note text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  is_reversed boolean NOT NULL DEFAULT false,
  reversed_transaction_id uuid REFERENCES public.inventory_transactions(id)
);
CREATE INDEX idx_inv_tx_date ON public.inventory_transactions(company_id, transaction_date DESC);
CREATE INDEX idx_inv_tx_source ON public.inventory_transactions(company_id, source_type, source_id);

CREATE TABLE public.inventory_transaction_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  transaction_id uuid NOT NULL REFERENCES public.inventory_transactions(id) ON DELETE CASCADE,
  item_id uuid NOT NULL REFERENCES public.items(id),
  lot_id uuid NULL REFERENCES public.lots(id),
  from_warehouse_id uuid NULL REFERENCES public.warehouses(id),
  from_location_id uuid NULL REFERENCES public.warehouse_locations(id),
  to_warehouse_id uuid NULL REFERENCES public.warehouses(id),
  to_location_id uuid NULL REFERENCES public.warehouse_locations(id),
  quantity numeric(18,4) NOT NULL CHECK(quantity > 0),
  uom_id uuid NOT NULL REFERENCES public.units_of_measure(id),
  unit_cost numeric(18,6),
  total_cost numeric(18,6),
  production_order_id uuid NULL REFERENCES public.production_orders(id),
  production_order_material_id uuid NULL REFERENCES public.production_order_materials(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (from_warehouse_id IS NOT NULL OR to_warehouse_id IS NOT NULL)
);
CREATE INDEX idx_inv_line_item ON public.inventory_transaction_lines(company_id, item_id);
CREATE INDEX idx_inv_line_lot ON public.inventory_transaction_lines(company_id, lot_id);
CREATE INDEX idx_inv_line_from_wh ON public.inventory_transaction_lines(company_id, from_warehouse_id);
CREATE INDEX idx_inv_line_to_wh ON public.inventory_transaction_lines(company_id, to_warehouse_id);

CREATE TABLE public.stock_balances (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  item_id uuid NOT NULL REFERENCES public.items(id),
  warehouse_id uuid NOT NULL REFERENCES public.warehouses(id),
  location_id uuid NULL REFERENCES public.warehouse_locations(id),
  lot_id uuid NULL REFERENCES public.lots(id),
  quantity_on_hand numeric(18,4) NOT NULL DEFAULT 0,
  quantity_reserved numeric(18,4) NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK(quantity_on_hand >= 0),
  CHECK(quantity_reserved >= 0),
  CHECK(quantity_reserved <= quantity_on_hand),
  UNIQUE NULLS NOT DISTINCT(company_id, item_id, warehouse_id, location_id, lot_id)
);
CREATE INDEX idx_stock_item_wh ON public.stock_balances(company_id, item_id, warehouse_id);
CREATE INDEX idx_stock_wh_item ON public.stock_balances(company_id, warehouse_id, item_id);
CREATE INDEX idx_stock_lot ON public.stock_balances(company_id, item_id, lot_id);

CREATE TABLE public.inventory_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  production_order_id uuid NOT NULL REFERENCES public.production_orders(id),
  production_order_material_id uuid NOT NULL REFERENCES public.production_order_materials(id),
  item_id uuid NOT NULL REFERENCES public.items(id),
  warehouse_id uuid NOT NULL REFERENCES public.warehouses(id),
  location_id uuid NULL REFERENCES public.warehouse_locations(id),
  lot_id uuid NULL REFERENCES public.lots(id),
  reserved_qty numeric(18,4) NOT NULL CHECK(reserved_qty > 0),
  consumed_qty numeric(18,4) NOT NULL DEFAULT 0 CHECK(consumed_qty >= 0),
  status text NOT NULL CHECK(status IN ('ACTIVE','PARTIALLY_CONSUMED','CONSUMED','RELEASED','CANCELLED')) DEFAULT 'ACTIVE',
  created_at timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz,
  CHECK(consumed_qty <= reserved_qty)
);
CREATE INDEX idx_res_order ON public.inventory_reservations(company_id, production_order_id, status);
CREATE INDEX idx_res_material ON public.inventory_reservations(production_order_material_id, status);

CREATE TABLE public.production_consumptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  production_order_id uuid NOT NULL REFERENCES public.production_orders(id),
  production_order_material_id uuid NOT NULL REFERENCES public.production_order_materials(id),
  item_id uuid NOT NULL REFERENCES public.items(id),
  lot_id uuid NULL REFERENCES public.lots(id),
  warehouse_id uuid NOT NULL REFERENCES public.warehouses(id),
  location_id uuid NULL REFERENCES public.warehouse_locations(id),
  quantity numeric(18,4) NOT NULL CHECK(quantity > 0),
  uom_id uuid NOT NULL REFERENCES public.units_of_measure(id),
  inventory_transaction_line_id uuid NOT NULL REFERENCES public.inventory_transaction_lines(id),
  consumed_at timestamptz NOT NULL DEFAULT now(),
  consumed_by uuid REFERENCES auth.users(id)
);

CREATE TABLE public.production_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id),
  production_order_id uuid NOT NULL REFERENCES public.production_orders(id),
  item_id uuid NOT NULL REFERENCES public.items(id),
  lot_id uuid NULL REFERENCES public.lots(id),
  warehouse_id uuid NOT NULL REFERENCES public.warehouses(id),
  location_id uuid NULL REFERENCES public.warehouse_locations(id),
  quantity_good numeric(18,4) NOT NULL CHECK(quantity_good >= 0),
  quantity_scrap numeric(18,4) NOT NULL DEFAULT 0 CHECK(quantity_scrap >= 0),
  uom_id uuid NOT NULL REFERENCES public.units_of_measure(id),
  inventory_transaction_line_id uuid NOT NULL REFERENCES public.inventory_transaction_lines(id),
  received_at timestamptz NOT NULL DEFAULT now(),
  received_by uuid REFERENCES auth.users(id)
);

-- ---------- inventory posting RPC ----------
CREATE OR REPLACE FUNCTION public.get_or_create_stock_balance(
  p_company_id uuid,
  p_item_id uuid,
  p_warehouse_id uuid,
  p_location_id uuid,
  p_lot_id uuid
)
RETURNS public.stock_balances LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_balance public.stock_balances%ROWTYPE;
BEGIN
  INSERT INTO public.stock_balances(company_id,item_id,warehouse_id,location_id,lot_id)
  VALUES(p_company_id,p_item_id,p_warehouse_id,p_location_id,p_lot_id)
  ON CONFLICT (company_id,item_id,warehouse_id,location_id,lot_id) DO NOTHING;

  SELECT * INTO v_balance
  FROM public.stock_balances
  WHERE company_id = p_company_id
    AND item_id = p_item_id
    AND warehouse_id = p_warehouse_id
    AND location_id IS NOT DISTINCT FROM p_location_id
    AND lot_id IS NOT DISTINCT FROM p_lot_id
  FOR UPDATE;

  RETURN v_balance;
END;
$$;

CREATE OR REPLACE FUNCTION public.post_inventory_transaction(
  p_company_id uuid,
  p_transaction_type text,
  p_source_type text DEFAULT NULL,
  p_source_id uuid DEFAULT NULL,
  p_reference_number text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_lines jsonb DEFAULT '[]'::jsonb
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_tx_id uuid;
  v_line jsonb;
  v_line_id uuid;
  v_item_id uuid;
  v_lot_id uuid;
  v_from_wh uuid;
  v_from_loc uuid;
  v_to_wh uuid;
  v_to_loc uuid;
  v_qty numeric(18,4);
  v_uom_id uuid;
  v_default_uom uuid;
  v_is_lot_tracked boolean;
  v_bal public.stock_balances%ROWTYPE;
BEGIN
  IF NOT public.has_company_role(p_company_id, ARRAY['ADMIN','WAREHOUSE','PLANNER','PRODUCTION_OPERATOR']) THEN
    RAISE EXCEPTION 'Not authorized for company %', p_company_id USING ERRCODE = '42501';
  END IF;

  IF jsonb_array_length(p_lines) = 0 THEN
    RAISE EXCEPTION 'Inventory transaction must contain at least one line';
  END IF;

  INSERT INTO public.inventory_transactions(company_id, transaction_type, source_type, source_id, reference_number, note, created_by)
  VALUES(p_company_id, p_transaction_type, p_source_type, p_source_id, p_reference_number, p_note, auth.uid())
  RETURNING id INTO v_tx_id;

  FOR v_line IN SELECT * FROM jsonb_array_elements(p_lines) LOOP
    v_item_id := (v_line->>'item_id')::uuid;
    v_lot_id := NULLIF(v_line->>'lot_id','')::uuid;
    v_from_wh := NULLIF(v_line->>'from_warehouse_id','')::uuid;
    v_from_loc := NULLIF(v_line->>'from_location_id','')::uuid;
    v_to_wh := NULLIF(v_line->>'to_warehouse_id','')::uuid;
    v_to_loc := NULLIF(v_line->>'to_location_id','')::uuid;
    v_qty := (v_line->>'quantity')::numeric;
    v_uom_id := (v_line->>'uom_id')::uuid;

    SELECT default_uom_id, is_lot_tracked INTO v_default_uom, v_is_lot_tracked
    FROM public.items WHERE id = v_item_id AND company_id = p_company_id;
    IF v_default_uom IS NULL THEN RAISE EXCEPTION 'Invalid item %', v_item_id; END IF;
    IF v_uom_id <> v_default_uom THEN RAISE EXCEPTION 'Posting function currently requires item default UOM'; END IF;
    IF v_is_lot_tracked AND v_lot_id IS NULL THEN RAISE EXCEPTION 'Lot is required for lot-tracked item %', v_item_id; END IF;
    IF v_qty <= 0 THEN RAISE EXCEPTION 'Quantity must be positive'; END IF;
    IF v_from_wh IS NULL AND v_to_wh IS NULL THEN RAISE EXCEPTION 'Line requires from or to warehouse'; END IF;

    IF p_transaction_type = 'TRANSFER' AND (v_from_wh IS NULL OR v_to_wh IS NULL) THEN
      RAISE EXCEPTION 'TRANSFER requires both from_warehouse_id and to_warehouse_id';
    ELSIF p_transaction_type IN ('PURCHASE_RECEIPT','PRODUCTION_RECEIPT','ADJUSTMENT_IN','RETURN') AND v_to_wh IS NULL THEN
      RAISE EXCEPTION '% requires to_warehouse_id', p_transaction_type;
    ELSIF p_transaction_type IN ('ADJUSTMENT_OUT','PRODUCTION_ISSUE','SCRAP','SALES_SHIPMENT') AND v_from_wh IS NULL THEN
      RAISE EXCEPTION '% requires from_warehouse_id', p_transaction_type;
    END IF;

    INSERT INTO public.inventory_transaction_lines(
      company_id, transaction_id, item_id, lot_id, from_warehouse_id, from_location_id,
      to_warehouse_id, to_location_id, quantity, uom_id, unit_cost, total_cost,
      production_order_id, production_order_material_id
    ) VALUES (
      p_company_id, v_tx_id, v_item_id, v_lot_id, v_from_wh, v_from_loc,
      v_to_wh, v_to_loc, v_qty, v_uom_id,
      NULLIF(v_line->>'unit_cost','')::numeric,
      NULLIF(v_line->>'total_cost','')::numeric,
      NULLIF(v_line->>'production_order_id','')::uuid,
      NULLIF(v_line->>'production_order_material_id','')::uuid
    ) RETURNING id INTO v_line_id;

    IF v_from_wh IS NOT NULL THEN
      v_bal := public.get_or_create_stock_balance(p_company_id, v_item_id, v_from_wh, v_from_loc, v_lot_id);
      IF v_bal.quantity_on_hand - v_qty < v_bal.quantity_reserved THEN
        RAISE EXCEPTION 'Insufficient available stock for item %', v_item_id;
      END IF;
      UPDATE public.stock_balances
      SET quantity_on_hand = quantity_on_hand - v_qty, updated_at = now()
      WHERE id = v_bal.id;
    END IF;

    IF v_to_wh IS NOT NULL THEN
      v_bal := public.get_or_create_stock_balance(p_company_id, v_item_id, v_to_wh, v_to_loc, v_lot_id);
      UPDATE public.stock_balances
      SET quantity_on_hand = quantity_on_hand + v_qty, updated_at = now()
      WHERE id = v_bal.id;
    END IF;
  END LOOP;

  RETURN v_tx_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reserve_production_material(
  p_production_order_material_id uuid,
  p_warehouse_id uuid,
  p_location_id uuid DEFAULT NULL,
  p_lot_id uuid DEFAULT NULL,
  p_qty numeric DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pom public.production_order_materials%ROWTYPE;
  v_po public.production_orders%ROWTYPE;
  v_balance public.stock_balances%ROWTYPE;
  v_qty numeric(18,4);
  v_res_id uuid;
BEGIN
  SELECT * INTO v_pom FROM public.production_order_materials WHERE id = p_production_order_material_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Production order material not found'; END IF;
  IF NOT public.has_company_role(v_pom.company_id, ARRAY['ADMIN','WAREHOUSE','PLANNER']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_po FROM public.production_orders WHERE id = v_pom.production_order_id;
  IF v_po.status NOT IN ('PLANNED','RELEASED') THEN RAISE EXCEPTION 'Can reserve only planned/released orders'; END IF;

  v_qty := COALESCE(p_qty, v_pom.planned_qty - v_pom.reserved_qty);
  IF v_qty <= 0 THEN RAISE EXCEPTION 'Nothing to reserve'; END IF;

  v_balance := public.get_or_create_stock_balance(v_pom.company_id, v_pom.item_id, p_warehouse_id, p_location_id, p_lot_id);
  IF v_balance.quantity_on_hand - v_balance.quantity_reserved < v_qty THEN
    RAISE EXCEPTION 'Insufficient available stock';
  END IF;

  UPDATE public.stock_balances SET quantity_reserved = quantity_reserved + v_qty, updated_at = now() WHERE id = v_balance.id;
  UPDATE public.production_order_materials SET reserved_qty = reserved_qty + v_qty WHERE id = v_pom.id;

  INSERT INTO public.inventory_reservations(company_id, production_order_id, production_order_material_id, item_id, warehouse_id, location_id, lot_id, reserved_qty)
  VALUES(v_pom.company_id, v_pom.production_order_id, v_pom.id, v_pom.item_id, p_warehouse_id, p_location_id, p_lot_id, v_qty)
  RETURNING id INTO v_res_id;

  RETURN v_res_id;
END;
$$;

-- ---------- audit ----------
CREATE TABLE public.audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid,
  table_name text NOT NULL,
  record_id uuid,
  action text NOT NULL CHECK(action IN ('INSERT','UPDATE','DELETE')),
  old_data jsonb,
  new_data jsonb,
  changed_by uuid REFERENCES auth.users(id),
  changed_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_company_time ON public.audit_log(company_id, changed_at DESC);
CREATE INDEX idx_audit_table_record ON public.audit_log(table_name, record_id);

CREATE OR REPLACE FUNCTION public.audit_row_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_company uuid;
  v_record uuid;
BEGIN
  v_company := COALESCE((to_jsonb(NEW)->>'company_id')::uuid, (to_jsonb(OLD)->>'company_id')::uuid);
  v_record := COALESCE((to_jsonb(NEW)->>'id')::uuid, (to_jsonb(OLD)->>'id')::uuid);
  INSERT INTO public.audit_log(company_id, table_name, record_id, action, old_data, new_data, changed_by)
  VALUES(v_company, TG_TABLE_NAME, v_record, TG_OP, to_jsonb(OLD), to_jsonb(NEW), auth.uid());
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER audit_items AFTER INSERT OR UPDATE OR DELETE ON public.items FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();
CREATE TRIGGER audit_boms AFTER INSERT OR UPDATE OR DELETE ON public.boms FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();
CREATE TRIGGER audit_bom_lines AFTER INSERT OR UPDATE OR DELETE ON public.bom_lines FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();
CREATE TRIGGER audit_production_orders AFTER INSERT OR UPDATE OR DELETE ON public.production_orders FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();
CREATE TRIGGER audit_stock_balances AFTER INSERT OR UPDATE OR DELETE ON public.stock_balances FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

-- ---------- RLS ----------
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_memberships ENABLE ROW LEVEL SECURITY;

CREATE POLICY companies_member_select ON public.companies FOR SELECT USING (id = ANY(public.current_company_ids()));
CREATE POLICY memberships_self_select ON public.company_memberships FOR SELECT USING (user_id = auth.uid() OR public.has_company_role(company_id, ARRAY['ADMIN']));
CREATE POLICY memberships_admin_manage ON public.company_memberships FOR ALL USING (public.has_company_role(company_id, ARRAY['ADMIN'])) WITH CHECK (public.has_company_role(company_id, ARRAY['ADMIN']));

-- Apply common company-scoped RLS policies.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'units_of_measure','items','unit_conversions','warehouses','warehouse_locations','lots',
    'boms','bom_lines','work_centers','machines','routings','routing_operations',
    'production_orders','production_order_materials','production_order_operations','production_operation_events',
    'inventory_transactions','inventory_transaction_lines','stock_balances','inventory_reservations',
    'production_consumptions','production_receipts','audit_log'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY %I_member_select ON public.%I FOR SELECT USING (public.is_company_member(company_id))', t, t);
    EXECUTE format('CREATE POLICY %I_staff_insert ON public.%I FOR INSERT WITH CHECK (public.has_company_role(company_id, ARRAY[''ADMIN'',''PLANNER'',''WAREHOUSE'',''PRODUCTION_OPERATOR'',''QUALITY'',''MANAGER'']))', t, t);
    EXECUTE format('CREATE POLICY %I_staff_update ON public.%I FOR UPDATE USING (public.has_company_role(company_id, ARRAY[''ADMIN'',''PLANNER'',''WAREHOUSE'',''PRODUCTION_OPERATOR'',''QUALITY'',''MANAGER''])) WITH CHECK (public.has_company_role(company_id, ARRAY[''ADMIN'',''PLANNER'',''WAREHOUSE'',''PRODUCTION_OPERATOR'',''QUALITY'',''MANAGER'']))', t, t);
  END LOOP;
END $$;


-- Translations inherit authorization from parent item.
ALTER TABLE public.item_translations ENABLE ROW LEVEL SECURITY;
CREATE POLICY item_translations_member_select ON public.item_translations
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM public.items i WHERE i.id = item_id AND public.is_company_member(i.company_id))
  );
CREATE POLICY item_translations_staff_insert ON public.item_translations
  FOR INSERT WITH CHECK (
    EXISTS (SELECT 1 FROM public.items i WHERE i.id = item_id AND public.has_company_role(i.company_id, ARRAY['ADMIN','PLANNER','MANAGER']))
  );
CREATE POLICY item_translations_staff_update ON public.item_translations
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM public.items i WHERE i.id = item_id AND public.has_company_role(i.company_id, ARRAY['ADMIN','PLANNER','MANAGER']))
  ) WITH CHECK (
    EXISTS (SELECT 1 FROM public.items i WHERE i.id = item_id AND public.has_company_role(i.company_id, ARRAY['ADMIN','PLANNER','MANAGER']))
  );

-- Prevent direct deletes of ledger rows by policy omission is not enough for service role; use trigger.
CREATE OR REPLACE FUNCTION public.prevent_delete()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Delete is not allowed on %. Use reversal/cancellation workflow.', TG_TABLE_NAME;
END;
$$;
CREATE TRIGGER no_delete_inventory_transactions BEFORE DELETE ON public.inventory_transactions FOR EACH ROW EXECUTE FUNCTION public.prevent_delete();
CREATE TRIGGER no_delete_inventory_transaction_lines BEFORE DELETE ON public.inventory_transaction_lines FOR EACH ROW EXECUTE FUNCTION public.prevent_delete();
