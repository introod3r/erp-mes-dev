'use client';

import { FormEvent, useEffect, useMemo, useState } from 'react';
import { AppNav } from './AppNav';
import { CompanySelect, useCompany } from './useCompany';

type Item = { id: string; item_code: string; name: string; default_uom_id: string; is_lot_tracked: boolean };
type Warehouse = { id: string; code: string; name: string; warehouse_type: string };
type Stock = { id: string; quantity_on_hand: number; quantity_reserved: number; items?: { item_code: string; name: string }; warehouses?: { code: string; name: string }; lots?: { lot_number: string } | null };

export function InventoryManager() {
  const { companies, companyId, setCompanyId } = useCompany();
  const [items, setItems] = useState<Item[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [stock, setStock] = useState<Stock[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [form, setForm] = useState({ item_id: '', warehouse_id: '', quantity: 1, transaction_type: 'PURCHASE_RECEIPT', reference_number: '', lot_number: '' });

  const selectedItem = useMemo(() => items.find((i) => i.id === form.item_id), [items, form.item_id]);

  async function load() {
    if (!companyId) return;
    const [itemRes, whRes, stockRes] = await Promise.all([
      fetch(`/api/items?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/warehouses?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/stock-balances?company_id=${companyId}`).then((r) => r.json()),
    ]);
    const itemList = (itemRes.data ?? []).filter((i: any) => i.is_active !== false && i.item_type !== 'SERVICE');
    const whList = whRes.data ?? [];
    setItems(itemList);
    setWarehouses(whList);
    setStock(stockRes.data ?? []);
    setForm((old) => ({ ...old, item_id: old.item_id || itemList[0]?.id || '', warehouse_id: old.warehouse_id || whList[0]?.id || '' }));
  }

  useEffect(() => { load(); }, [companyId]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    if (!selectedItem) { setMessage('Select item'); return; }

    let lotId: string | null = null;
    if (selectedItem.is_lot_tracked) {
      if (!form.lot_number.trim()) { setMessage('Lot number is required for this item'); return; }
      const lotRes = await fetch('/api/lots', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ company_id: companyId, item_id: selectedItem.id, lot_number: form.lot_number.trim() }),
      });
      const lotJson = await lotRes.json();
      if (!lotRes.ok) { setMessage(lotJson.error?.message ?? JSON.stringify(lotJson.error)); return; }
      lotId = lotJson.data.id;
    }

    const res = await fetch('/api/inventory/post', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        company_id: companyId,
        transaction_type: form.transaction_type,
        reference_number: form.reference_number || null,
        lines: [{
          item_id: selectedItem.id,
          to_warehouse_id: form.warehouse_id,
          quantity: Number(form.quantity),
          uom_id: selectedItem.default_uom_id,
          lot_id: lotId,
        }],
      }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Inventory posted. Transaction: ${json.transaction_id}`);
    setForm({ ...form, quantity: 1, reference_number: '', lot_number: '' });
    await load();
  }

  return (
    <>
      <AppNav />
      <main className="pageShell">
        <div className="pageHeader">
          <div><div className="eyebrow">Inventory execution</div><h1>Inventory</h1><p>Post initial receipts/adjustments and review stock balances. Critical posting is done through the database ledger RPC.</p></div>
          <CompanySelect companies={companies} companyId={companyId} onChange={setCompanyId} />
        </div>

        <section className="twoColumn">
          <form className="formCard" onSubmit={submit}>
            <h2>Post inventory in</h2>
            <label>Type<select value={form.transaction_type} onChange={(e) => setForm({ ...form, transaction_type: e.target.value })}><option>PURCHASE_RECEIPT</option><option>ADJUSTMENT_IN</option></select></label>
            <label>Item<select value={form.item_id} onChange={(e) => setForm({ ...form, item_id: e.target.value })} required>{items.map((item) => <option key={item.id} value={item.id}>{item.item_code} - {item.name}</option>)}</select></label>
            <label>Warehouse<select value={form.warehouse_id} onChange={(e) => setForm({ ...form, warehouse_id: e.target.value })} required>{warehouses.map((wh) => <option key={wh.id} value={wh.id}>{wh.code} - {wh.name}</option>)}</select></label>
            <label>Quantity<input type="number" min="0.0001" step="0.0001" value={form.quantity} onChange={(e) => setForm({ ...form, quantity: Number(e.target.value) })} required /></label>
            {selectedItem?.is_lot_tracked && <label>Lot number<input value={form.lot_number} onChange={(e) => setForm({ ...form, lot_number: e.target.value })} required placeholder="LOT-2026-0001" /></label>}
            <label>Reference<input value={form.reference_number} onChange={(e) => setForm({ ...form, reference_number: e.target.value })} placeholder="GRN / adjustment number" /></label>
            {message && <div className="formMessage">{message}</div>}
            <button className="button" disabled={!companyId || !items.length || !warehouses.length}>Post inventory</button>
          </form>

          <section className="panel">
            <h2>Stock balances</h2>
            <div className="tableWrap"><table><thead><tr><th>Item</th><th>Warehouse</th><th>Lot</th><th>On hand</th><th>Reserved</th><th>Available</th></tr></thead><tbody>{stock.map((s) => <tr key={s.id}><td>{s.items?.item_code} - {s.items?.name}</td><td>{s.warehouses?.code}</td><td>{s.lots?.lot_number ?? ''}</td><td>{s.quantity_on_hand}</td><td>{s.quantity_reserved}</td><td>{Number(s.quantity_on_hand) - Number(s.quantity_reserved)}</td></tr>)}</tbody></table></div>
          </section>
        </section>
      </main>
    </>
  );
}
