import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';

const schema = z.object({
  company_id: z.string().uuid(),
  request_number: z.string().min(1),
  correction_type: z.enum(['INVENTORY_TRANSACTION','PRODUCTION_CONSUMPTION','PRODUCTION_RECEIPT','OPERATION_EVENT']),
  target_id: z.string().uuid(),
  reason: z.string().min(1),
});

export async function GET(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const companyId = req.nextUrl.searchParams.get('company_id');
  if (!companyId) return NextResponse.json({ error: 'company_id is required' }, { status: 400 });
  const { data, error } = await supabase.from('correction_requests').select('*').eq('company_id', companyId).order('requested_at', { ascending: false });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function POST(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const { data, error } = await supabase.rpc('create_correction_request', {
    p_company_id: parsed.data.company_id,
    p_request_number: parsed.data.request_number,
    p_correction_type: parsed.data.correction_type,
    p_target_id: parsed.data.target_id,
    p_reason: parsed.data.reason,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ id: data }, { status: 201 });
}
