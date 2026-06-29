import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';

const schema = z.object({
  warehouse_id: z.string().uuid(),
  location_id: z.string().uuid().optional().nullable(),
  lot_id: z.string().uuid().optional().nullable(),
  quantity: z.number().positive().optional().nullable(),
});

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const { data, error } = await supabase.rpc('reserve_production_material', {
    p_production_order_material_id: id,
    p_warehouse_id: parsed.data.warehouse_id,
    p_location_id: parsed.data.location_id ?? null,
    p_lot_id: parsed.data.lot_id ?? null,
    p_qty: parsed.data.quantity ?? null,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ reservation_id: data }, { status: 201 });
}
