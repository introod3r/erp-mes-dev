-- Manual concurrency test outline.
-- Run these in two separate SQL sessions after adapting IDs.

-- Session A:
-- BEGIN;
-- SELECT * FROM public.stock_balances WHERE id = '<stock_balance_id>' FOR UPDATE;
-- SELECT pg_sleep(15);
-- COMMIT;

-- Session B while Session A sleeps:
-- Try reserve_production_order_materials() for an order using the same stock.
-- Expected: it waits or skips locked rows depending on function. Stock must not over-reserve.

-- Assertions after both sessions:
-- SELECT quantity_on_hand, quantity_reserved, quantity_on_hand - quantity_reserved AS available
-- FROM public.stock_balances
-- WHERE id = '<stock_balance_id>';
-- Expected: quantity_reserved <= quantity_on_hand and available >= 0.
