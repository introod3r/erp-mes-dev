import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';

const schema = z.object({
  company_id: z.string().uuid(),
  bom_id: z.string().uuid(),
  component_item_id: z.string().uuid(),
  quantity_per: z.number().positive(),
  uom_id: z.string().uuid(),
  scrap_factor_percent: z.number().min(0).default(0),
  issue_method: z.enum(['MANUAL','BACKFLUSH']).default('MANUAL'),
  operation_sequence: z.number().int().optional().nullable(),
});

export async function GET(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const bomId = req.nextUrl.searchParams.get('bom_id');
  if (!bomId) return NextResponse.json({ error: 'bom_id is required' }, { status: 400 });
  const { data, error } = await supabase
    .from('bom_lines')
    .select('id,component_item_id,quantity_per,uom_id,scrap_factor_percent,issue_method,operation_sequence,items!bom_lines_component_item_id_fkey(item_code,name),units_of_measure(code,symbol)')
    .eq('bom_id', bomId)
    .order('created_at');
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function POST(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const { data, error } = await supabase.from('bom_lines').insert(parsed.data).select().single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data }, { status: 201 });
}
