import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from('inventory_reservations')
    .select('id,production_order_material_id,item_id,warehouse_id,location_id,lot_id,reserved_qty,consumed_qty,released_qty,status,created_at,released_at,items(item_code,name),warehouses(code,name),lots(lot_number)')
    .eq('production_order_id', id)
    .order('created_at', { ascending: false });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
