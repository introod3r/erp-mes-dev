import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();

  const { data, error } = await supabase
    .from('production_operation_events')
    .select('id,event_type,event_time,quantity_good,quantity_scrap,reason_code,note,is_reversed,machine_id,production_order_operations!inner(production_order_id,sequence_no,operation_code,operation_name),machines(code,name)')
    .eq('production_order_operations.production_order_id', id)
    .order('event_time', { ascending: false })
    .limit(200);

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
