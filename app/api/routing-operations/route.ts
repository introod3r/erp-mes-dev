import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';

const schema = z.object({
  company_id: z.string().uuid(),
  routing_id: z.string().uuid(),
  sequence_no: z.number().int().positive(),
  operation_code: z.string().min(1).max(80),
  operation_name: z.string().min(1).max(255),
  work_center_id: z.string().uuid(),
  setup_time_minutes: z.number().min(0).default(0),
  run_time_minutes_per_unit: z.number().min(0).default(0),
  labor_required: z.boolean().default(true),
  machine_required: z.boolean().default(true),
});

export async function GET(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const routingId = req.nextUrl.searchParams.get('routing_id');
  if (!routingId) return NextResponse.json({ error: 'routing_id is required' }, { status: 400 });
  const { data, error } = await supabase
    .from('routing_operations')
    .select('id,sequence_no,operation_code,operation_name,work_center_id,setup_time_minutes,run_time_minutes_per_unit,labor_required,machine_required,work_centers(code,name)')
    .eq('routing_id', routingId)
    .order('sequence_no');
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function POST(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const { data, error } = await supabase.from('routing_operations').insert(parsed.data).select().single();
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data }, { status: 201 });
}
