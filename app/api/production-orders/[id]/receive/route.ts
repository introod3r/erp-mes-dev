import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';

const schema = z.object({
  warehouse_id: z.string().uuid(),
  quantity_good: z.number().min(0),
  quantity_scrap: z.number().min(0).default(0),
  scrap_warehouse_id: z.string().uuid().optional().nullable(),
  lot_number: z.string().optional().nullable(),
  finish_order: z.boolean().default(false),
}).refine((v) => v.quantity_good > 0 || v.quantity_scrap > 0, {
  message: 'At least one quantity must be positive',
});

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });

  const { data, error } = await supabase.rpc('receive_finished_goods', {
    p_production_order_id: id,
    p_warehouse_id: parsed.data.warehouse_id,
    p_quantity_good: parsed.data.quantity_good,
    p_quantity_scrap: parsed.data.quantity_scrap,
    p_scrap_warehouse_id: parsed.data.scrap_warehouse_id ?? null,
    p_lot_number: parsed.data.lot_number ?? null,
    p_finish_order: parsed.data.finish_order,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ transaction_id: data }, { status: 201 });
}
