import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';

const schema = z.object({
  company_id: z.string().uuid(),
  item_id: z.string().uuid(),
  routing_code: z.string().min(1).max(80),
  version: z.string().min(1).max(40),
  status: z.enum(['DRAFT','ACTIVE','OBSOLETE']).default('DRAFT'),
  valid_from: z.string().min(10),
  valid_to: z.string().optional().nullable(),
  is_default: z.boolean().default(false),
});

export async function GET(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const companyId = req.nextUrl.searchParams.get('company_id');
  if (!companyId) return NextResponse.json({ error: 'company_id is required' }, { status: 400 });
  const { data, error } = await supabase
    .from('routings')
    .select('id,routing_code,version,status,valid_from,valid_to,is_default,item_id,items(item_code,name)')
    .eq('company_id', companyId)
    .order('routing_code');
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function POST(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const { data, error } = await supabase.from('routings').insert(parsed.data).select().single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data }, { status: 201 });
}
