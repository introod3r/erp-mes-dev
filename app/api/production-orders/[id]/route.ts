import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from('production_orders')
    .select('id,company_id,order_number,status,planned_quantity,produced_quantity,scrap_quantity,uom_id,bom_id,routing_id,planned_start_date,planned_end_date,actual_start_date,actual_end_date,items(item_code,name),units_of_measure(code,symbol)')
    .eq('id', id)
    .single();

  if (error) return NextResponse.json({ error: error.message }, { status: 404 });
  return NextResponse.json({ data });
}
