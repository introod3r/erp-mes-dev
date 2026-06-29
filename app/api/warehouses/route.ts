import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { warehouseCreateSchema } from '@/lib/api';

export async function GET(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const companyId = req.nextUrl.searchParams.get('company_id');
  if (!companyId) return NextResponse.json({ error: 'company_id is required' }, { status: 400 });

  const { data, error } = await supabase
    .from('warehouses')
    .select('id,code,name,warehouse_type,is_active')
    .eq('company_id', companyId)
    .order('code');

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function POST(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const parsed = warehouseCreateSchema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const { data, error } = await supabase.from('warehouses').insert(parsed.data).select().single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data }, { status: 201 });
}
