import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { productionOrderCreateSchema } from '@/lib/api';

export async function GET(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const companyId = req.nextUrl.searchParams.get('company_id');
  const status = req.nextUrl.searchParams.get('status');
  if (!companyId) return NextResponse.json({ error: 'company_id is required' }, { status: 400 });

  let query = supabase
    .from('production_orders')
    .select('id,order_number,status,planned_quantity,produced_quantity,scrap_quantity,planned_start_date,planned_end_date,items(item_code,name)')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(100);

  if (status) query = query.eq('status', status);

  const { data, error } = await query;
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function POST(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const parsed = productionOrderCreateSchema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const { data: userResult } = await supabase.auth.getUser();
  const payload = { ...parsed.data, created_by: userResult.user?.id ?? null };

  const { data, error } = await supabase.from('production_orders').insert(payload).select().single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data }, { status: 201 });
}
