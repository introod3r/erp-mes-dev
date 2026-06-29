import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { z } from 'zod';

const schema = z.object({
  company_id: z.string().uuid(),
  hold_number: z.string().min(1),
  item_id: z.string().uuid(),
  source_warehouse_id: z.string().uuid(),
  hold_warehouse_id: z.string().uuid(),
  quantity: z.number().positive(),
  lot_id: z.string().uuid().optional().nullable(),
  source_location_id: z.string().uuid().optional().nullable(),
  hold_location_id: z.string().uuid().optional().nullable(),
  ncr_id: z.string().uuid().optional().nullable(),
  reason_code: z.string().optional().nullable(),
  note: z.string().optional().nullable(),
});

export async function GET(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const companyId = req.nextUrl.searchParams.get('company_id');
  if (!companyId) return NextResponse.json({ error: 'company_id is required' }, { status: 400 });
  const { data, error } = await supabase
    .from('quality_holds')
    .select('id,hold_number,ncr_id,item_id,lot_id,source_warehouse_id,hold_warehouse_id,quantity,remaining_qty,status,reason_code,note,created_at,items(item_code,name),lots(lot_number),source:warehouses!quality_holds_source_warehouse_id_fkey(code,name),hold:warehouses!quality_holds_hold_warehouse_id_fkey(code,name),nonconformance_reports(ncr_number,status)')
    .eq('company_id', companyId)
    .order('created_at', { ascending: false });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}

export async function POST(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const parsed = schema.safeParse(await req.json());
  if (!parsed.success) return NextResponse.json({ error: parsed.error.flatten() }, { status: 400 });
  const { data, error } = await supabase.rpc('create_quality_hold', {
    p_company_id: parsed.data.company_id,
    p_hold_number: parsed.data.hold_number,
    p_item_id: parsed.data.item_id,
    p_source_warehouse_id: parsed.data.source_warehouse_id,
    p_hold_warehouse_id: parsed.data.hold_warehouse_id,
    p_quantity: parsed.data.quantity,
    p_lot_id: parsed.data.lot_id ?? null,
    p_source_location_id: parsed.data.source_location_id ?? null,
    p_hold_location_id: parsed.data.hold_location_id ?? null,
    p_ncr_id: parsed.data.ncr_id ?? null,
    p_reason_code: parsed.data.reason_code ?? null,
    p_note: parsed.data.note ?? null,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ id: data }, { status: 201 });
}
