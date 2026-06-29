import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';

const schema = z.object({
  company_id: z.string().uuid(),
  ncr_number: z.string().min(1),
  description: z.string().min(1),
  item_id: z.string().uuid().optional().nullable(),
  lot_id: z.string().uuid().optional().nullable(),
  source_type: z.string().optional().nullable(),
  source_id: z.string().uuid().optional().nullable(),
  severity: z.enum(['LOW','MEDIUM','HIGH','CRITICAL']).default('MEDIUM'),
});

export async function GET(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const companyId = req.nextUrl.searchParams.get('company_id');
  if (!companyId) return NextResponse.json({ error: 'company_id is required' }, { status: 400 });
  const { data, error } = await supabase
    .from('nonconformance_reports')
    .select('id,ncr_number,severity,status,description,disposition,created_at,item_id,lot_id,items(item_code,name),lots(lot_number)')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function POST(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const { data, error } = await supabase.rpc('create_nonconformance_report', {
    p_company_id: parsed.data.company_id,
    p_ncr_number: parsed.data.ncr_number,
    p_description: parsed.data.description,
    p_item_id: parsed.data.item_id ?? null,
    p_lot_id: parsed.data.lot_id ?? null,
    p_source_type: parsed.data.source_type ?? null,
    p_source_id: parsed.data.source_id ?? null,
    p_severity: parsed.data.severity,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ id: data }, { status: 201 });
}
