'use client';

import { FormEvent, useEffect, useState } from 'react';
import { AppNav } from './AppNav';
import { CompanySelect, useCompany } from './useCompany';

type Uom = { id: string; code: string; symbol: string; name: string };
type Item = { id: string; item_code: string; item_type: string; name: string; is_lot_tracked: boolean; is_active: boolean };

const itemTypes = ['RAW_MATERIAL', 'SEMI_FINISHED', 'FINISHED_GOOD', 'CONSUMABLE', 'SERVICE'] as const;

export function ItemsManager() {
  const { companies, companyId, setCompanyId } = useCompany();
  const [uoms, setUoms] = useState<Uom[]>([]);
  const [items, setItems] = useState<Item[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [form, setForm] = useState({ item_code: '', name: '', item_type: 'RAW_MATERIAL', default_uom_id: '', is_lot_tracked: false });

  async function load() {
    if (!companyId) return;
    const [uomRes, itemRes] = await Promise.all([
      fetch(`/api/uoms?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/items?company_id=${companyId}`).then((r) => r.json()),
    ]);
    setUoms(uomRes.data ?? []);
    setItems(itemRes.data ?? []);
    setForm((old) => ({ ...old, default_uom_id: old.default_uom_id || uomRes.data?.[0]?.id || '' }));
  }

  useEffect(() => { load(); }, [companyId]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    const payload = {
      company_id: companyId,
      item_code: form.item_code,
      name: form.name,
      item_type: form.item_type,
      default_uom_id: form.default_uom_id,
      is_lot_tracked: form.is_lot_tracked,
      is_stocked: form.item_type !== 'SERVICE',
      is_purchased: ['RAW_MATERIAL', 'CONSUMABLE', 'SERVICE'].includes(form.item_type),
      is_manufactured: ['SEMI_FINISHED', 'FINISHED_GOOD'].includes(form.item_type),
      is_sellable: form.item_type === 'FINISHED_GOOD',
    };
    const res = await fetch('/api/items', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error?.message ?? JSON.stringify(json.error)); return; }
    setForm({ ...form, item_code: '', name: '', is_lot_tracked: false });
    await load();
  }

  return (
    <>
      <AppNav />
      <main className="pageShell">
        <div className="pageHeader">
          <div><div className="eyebrow">Master data</div><h1>Items</h1><p>Create raw materials, semi-finished goods, finished goods, consumables, and services.</p></div>
          <CompanySelect companies={companies} companyId={companyId} onChange={setCompanyId} />
        </div>

        <section className="twoColumn">
          <form className="formCard" onSubmit={submit}>
            <h2>New item</h2>
            <label>Code<input value={form.item_code} onChange={(e) => setForm({ ...form, item_code: e.target.value })} required /></label>
            <label>Name<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required /></label>
            <label>Type<select value={form.item_type} onChange={(e) => setForm({ ...form, item_type: e.target.value })}>{itemTypes.map((type) => <option key={type}>{type}</option>)}</select></label>
            <label>Default UOM<select value={form.default_uom_id} onChange={(e) => setForm({ ...form, default_uom_id: e.target.value })} required>{uoms.map((uom) => <option key={uom.id} value={uom.id}>{uom.code} - {uom.name}</option>)}</select></label>
            <label className="checkboxRow"><input type="checkbox" checked={form.is_lot_tracked} onChange={(e) => setForm({ ...form, is_lot_tracked: e.target.checked })} /> Lot-tracked</label>
            {message && <div className="formMessage">{message}</div>}
            <button className="button" disabled={!companyId || !uoms.length}>Create item</button>
          </form>

          <section className="panel">
            <h2>Items list</h2>
            <div className="tableWrap">
              <table><thead><tr><th>Code</th><th>Name</th><th>Type</th><th>Lot</th></tr></thead><tbody>{items.map((item) => <tr key={item.id}><td>{item.item_code}</td><td>{item.name}</td><td>{item.item_type}</td><td>{item.is_lot_tracked ? 'Yes' : 'No'}</td></tr>)}</tbody></table>
            </div>
          </section>
        </section>
      </main>
    </>
  );
}
