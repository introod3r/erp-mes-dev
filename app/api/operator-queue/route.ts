import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function GET(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const companyId = req.nextUrl.searchParams.get('company_id');
  const workCenterId = req.nextUrl.searchParams.get('work_center_id');
  if (!companyId) return NextResponse.json({ error: 'company_id is required' }, { status: 400 });

  let query = supabase
    .from('production_order_operations')
    .select('id,sequence_no,operation_code,operation_name,status,planned_quantity,completed_quantity,scrap_quantity,work_center_id,production_orders(id,order_number,status,planned_quantity,items(item_code,name)),work_centers(code,name),machines(code,name)')
    .eq('company_id', companyId)
    .in('status', ['READY','IN_PROGRESS','PAUSED'])
    .order('sequence_no');

  if (workCenterId) query = query.eq('work_center_id', workCenterId);

  const { data, error } = await query.limit(100);
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
