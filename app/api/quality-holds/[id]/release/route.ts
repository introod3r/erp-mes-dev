import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';
const schema = z.object({ quantity: z.number().positive().optional().nullable(), to_warehouse_id: z.string().uuid().optional().nullable(), note: z.string().optional().nullable() }).optional();
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const body = await req.json().catch(() => ({}));
  const parsed = schema.safeParse(body);
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const { data, error } = await supabase.rpc('release_quality_hold', {
    p_quality_hold_id: id,
    p_quantity: parsed.data?.quantity ?? null,
    p_to_warehouse_id: parsed.data?.to_warehouse_id ?? null,
    p_to_location_id: null,
    p_note: parsed.data?.note ?? null,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ transaction_id: data }, { status: 201 });
}
