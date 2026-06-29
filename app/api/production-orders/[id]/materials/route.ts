import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from('production_order_materials')
    .select('id,item_id,planned_qty,reserved_qty,issued_qty,consumed_qty,uom_id,issue_method,operation_sequence,items(item_code,name),units_of_measure(code,symbol)')
    .eq('production_order_id', id)
    .order('operation_sequence', { ascending: true, nullsFirst: false });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ data });
}
