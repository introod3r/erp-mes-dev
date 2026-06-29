import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';
const schema = z.object({ scrap_warehouse_id: z.string().uuid(), quantity: z.number().positive().optional().nullable(), note: z.string().optional().nullable() });
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const { data, error } = await supabase.rpc('scrap_quality_hold', {
    p_quality_hold_id: id,
    p_scrap_warehouse_id: parsed.data.scrap_warehouse_id,
    p_quantity: parsed.data.quantity ?? null,
    p_note: parsed.data.note ?? null,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ transaction_id: data }, { status: 201 });
}
