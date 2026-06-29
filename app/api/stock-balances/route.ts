import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function GET(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const companyId = req.nextUrl.searchParams.get('company_id');
  const itemId = req.nextUrl.searchParams.get('item_id');
  const warehouseId = req.nextUrl.searchParams.get('warehouse_id');
  if (!companyId) return NextResponse.json({ error: 'company_id is required' }, { status: 400 });

  let query = supabase
    .from('stock_balances')
    .select('id,item_id,warehouse_id,location_id,lot_id,quantity_on_hand,quantity_reserved,items(item_code,name),warehouses(code,name),lots(lot_number)')
    .eq('company_id', companyId);

  if (itemId) query = query.eq('item_id', itemId);
  if (warehouseId) query = query.eq('warehouse_id', warehouseId);

  const { data, error } = await query.order('updated_at', { ascending: false });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
