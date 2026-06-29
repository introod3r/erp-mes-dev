-- RLS hardening for critical inventory/production ledger tables.
-- Apply after 010_quality_hold_ncr.sql
-- Goal: direct client writes to critical transaction/state tables are removed.
-- Mutations must go through SECURITY DEFINER RPC workflows.

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'inventory_transactions',
    'inventory_transaction_lines',
    'stock_balances',
    'inventory_reservations',
    'production_consumptions',
    'production_receipts',
    'production_operation_events',
    'quality_holds',
    'nonconformance_reports',
    'audit_log'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_staff_insert', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_staff_update', t);
  END LOOP;
END $$;

-- Keep SELECT policies from the base migration. Do not add direct INSERT/UPDATE policies here.
-- SECURITY DEFINER RPC functions remain the write boundary for these tables.

COMMENT ON TABLE public.inventory_transactions IS 'Immutable inventory ledger header. Direct client writes disabled by RLS hardening; use RPC workflows.';
COMMENT ON TABLE public.inventory_transaction_lines IS 'Immutable inventory ledger lines. Direct client writes disabled by RLS hardening; use RPC workflows.';
COMMENT ON TABLE public.stock_balances IS 'Current stock balance cache. Direct client writes disabled by RLS hardening; use RPC workflows.';
COMMENT ON TABLE public.inventory_reservations IS 'Material reservations. Direct client writes disabled by RLS hardening; use reservation RPC workflows.';
COMMENT ON TABLE public.production_consumptions IS 'Production material issue records. Direct client writes disabled by RLS hardening; use consumption RPC workflows.';
COMMENT ON TABLE public.production_receipts IS 'Production receipt records. Direct client writes disabled by RLS hardening; use receipt RPC workflows.';
COMMENT ON TABLE public.production_operation_events IS 'MES event log. Direct client writes disabled by RLS hardening; use MES RPC workflows.';
