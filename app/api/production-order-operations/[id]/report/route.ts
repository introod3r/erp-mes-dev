import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';

const schema = z.object({
  quantity_good: z.number().min(0).default(0),
  quantity_scrap: z.number().min(0).default(0),
  reason_code: z.string().optional().nullable(),
  note: z.string().optional().nullable(),
  complete: z.boolean().default(false),
});

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const { data, error } = await supabase.rpc('report_production_operation', {
    p_operation_id: id,
    p_quantity_good: parsed.data.quantity_good,
    p_quantity_scrap: parsed.data.quantity_scrap,
    p_reason_code: parsed.data.reason_code ?? null,
    p_note: parsed.data.note ?? null,
    p_complete: parsed.data.complete,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ event_id: data }, { status: 201 });
}
