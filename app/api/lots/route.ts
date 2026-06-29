import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';

const schema = z.object({
  company_id: z.string().uuid(),
  item_id: z.string().uuid(),
  lot_number: z.string().min(1).max(120),
  supplier_lot_number: z.string().optional().nullable(),
});

export async function GET(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const companyId = req.nextUrl.searchParams.get('company_id');
  const itemId = req.nextUrl.searchParams.get('item_id');
  if (!companyId) return NextResponse.json({ error: 'company_id is required' }, { status: 400 });
  let query = supabase.from('lots').select('id,item_id,lot_number,supplier_lot_number,created_at,items(item_code,name)').eq('company_id', companyId).order('created_at', { ascending: false });
  if (itemId) query = query.eq('item_id', itemId);
  const { data, error } = await query;
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function POST(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const { data, error } = await supabase.from('lots').insert(parsed.data).select().single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data }, { status: 201 });
}
