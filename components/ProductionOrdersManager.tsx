'use client';

import Link from 'next/link';
import { FormEvent, useEffect, useState } from 'react';
import { AppNav } from './AppNav';
import { CompanySelect, useCompany } from './useCompany';

type Item = { id: string; item_code: string; name: string; item_type: string; default_uom_id: string };
type Order = { id: string; order_number: string; status: string; planned_quantity: number; produced_quantity: number; scrap_quantity: number; items?: { item_code: string; name: string } };

export function ProductionOrdersManager() {
  const { companies, companyId, setCompanyId } = useCompany();
  const [items, setItems] = useState<Item[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [form, setForm] = useState({ order_number: '', item_id: '', planned_quantity: 1 });

  async function load() {
    if (!companyId) return;
    const [itemRes, orderRes] = await Promise.all([
      fetch(`/api/items?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/production-orders?company_id=${companyId}`).then((r) => r.json()),
    ]);
    const manufactured = (itemRes.data ?? []).filter((i: Item) => ['SEMI_FINISHED', 'FINISHED_GOOD'].includes(i.item_type));
    setItems(manufactured);
    setOrders(orderRes.data ?? []);
    setForm((old) => ({ ...old, item_id: old.item_id || manufactured[0]?.id || '' }));
  }

  useEffect(() => { load(); }, [companyId]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    const item = items.find((i) => i.id === form.item_id);
    if (!item) { setMessage('Select a manufactured item'); return; }
    const payload = {
      company_id: companyId,
      order_number: form.order_number,
      item_id: form.item_id,
      planned_quantity: Number(form.planned_quantity),
      uom_id: item.default_uom_id,
      priority: 100,
    };
    const res = await fetch('/api/production-orders', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error?.message ?? JSON.stringify(json.error)); return; }
    setForm({ ...form, order_number: '', planned_quantity: 1 });
    await load();
  }

  async function release(orderId: string) {
    setMessage(null);
    const res = await fetch('/api/production-orders/release', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ production_order_id: orderId }) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    await load();
  }

  return (
    <>
      <AppNav />
      <main className="pageShell">
        <div className="pageHeader">
          <div><div className="eyebrow">Production</div><h1>Production orders</h1><p>Create planned orders and release them once BOM/routing master data exists.</p></div>
          <CompanySelect companies={companies} companyId={companyId} onChange={setCompanyId} />
        </div>
        <section className="twoColumn">
          <form className="formCard" onSubmit={submit}>
            <h2>New production order</h2>
            <label>Order number<input value={form.order_number} onChange={(e) => setForm({ ...form, order_number: e.target.value })} required placeholder="PO-2026-0001" /></label>
            <label>Manufactured item<select value={form.item_id} onChange={(e) => setForm({ ...form, item_id: e.target.value })} required>{items.map((item) => <option key={item.id} value={item.id}>{item.item_code} - {item.name}</option>)}</select></label>
            <label>Planned quantity<input type="number" min="0.0001" step="0.0001" value={form.planned_quantity} onChange={(e) => setForm({ ...form, planned_quantity: Number(e.target.value) })} required /></label>
            {message && <div className="formMessage">{message}</div>}
            <button className="button" disabled={!companyId || !items.length}>Create order</button>
          </form>
          <section className="panel">
            <h2>Latest production orders</h2>
            <div className="tableWrap"><table><thead><tr><th>Order</th><th>Item</th><th>Status</th><th>Planned</th><th></th></tr></thead><tbody>{orders.map((o) => <tr key={o.id}><td><Link className="tableLink" href={`/production-orders/${o.id}`}>{o.order_number}</Link></td><td>{o.items?.item_code}</td><td><span className="badge">{o.status}</span></td><td>{o.planned_quantity}</td><td>{o.status === 'PLANNED' && <button className="button small" onClick={() => release(o.id)}>Release</button>}</td></tr>)}</tbody></table></div>
          </section>
        </section>
      </main>
    </>
  );
}
