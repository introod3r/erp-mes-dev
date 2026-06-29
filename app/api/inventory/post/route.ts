import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServerClient } from '@/lib/supabase/server';

export async function POST(req: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const body = await req.json();

  const required = ['company_id', 'transaction_type', 'lines'];
  for (const key of required) {
    if (!(key in body)) return NextResponse.json({ error: `${key} is required` }, { status: 400 });
  }

  // Critical inventory mutations are delegated to the database RPC so stock rows
  // are locked and the immutable ledger + balance cache stay consistent.
  const { data, error } = await supabase.rpc('post_inventory_transaction', {
    p_company_id: body.company_id,
    p_transaction_type: body.transaction_type,
    p_source_type: body.source_type ?? null,
    p_source_id: body.source_id ?? null,
    p_reference_number: body.reference_number ?? null,
    p_note: body.note ?? null,
    p_lines: body.lines,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ transaction_id: data }, { status: 201 });
}
