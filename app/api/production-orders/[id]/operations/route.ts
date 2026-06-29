import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from('production_order_operations')
    .select('id,sequence_no,operation_code,operation_name,planned_setup_time_minutes,planned_run_time_minutes,actual_setup_time_minutes,actual_run_time_minutes,planned_quantity,completed_quantity,scrap_quantity,status,started_at,completed_at,work_centers(code,name),machines(code,name)')
    .eq('production_order_id', id)
    .order('sequence_no');

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
