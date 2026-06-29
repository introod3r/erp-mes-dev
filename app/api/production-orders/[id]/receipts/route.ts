import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from('production_receipts')
    .select('id,item_id,warehouse_id,lot_id,quantity_good,quantity_scrap,received_at,is_reversed,items(item_code,name),warehouses(code,name),lots(lot_number)')
    .eq('production_order_id', id)
    .order('received_at', { ascending: false });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
