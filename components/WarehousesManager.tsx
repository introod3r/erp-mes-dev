'use client';

import { FormEvent, useEffect, useState } from 'react';
import { AppNav } from './AppNav';
import { CompanySelect, useCompany } from './useCompany';

type Warehouse = { id: string; code: string; name: string; warehouse_type: string; is_active: boolean };
const types = ['RAW_MATERIAL', 'WIP', 'FINISHED_GOODS', 'SCRAP', 'QUALITY', 'GENERAL', 'SUBCONTRACTOR'] as const;

export function WarehousesManager() {
  const { companies, companyId, setCompanyId } = useCompany();
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [form, setForm] = useState({ code: '', name: '', warehouse_type: 'RAW_MATERIAL' });

  async function load() {
    if (!companyId) return;
    const res = await fetch(`/api/warehouses?company_id=${companyId}`);
    const json = await res.json();
    setWarehouses(json.data ?? []);
  }

  useEffect(() => { load(); }, [companyId]);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    const res = await fetch('/api/warehouses', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...form, company_id: companyId }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error?.message ?? JSON.stringify(json.error)); return; }
    setForm({ code: '', name: '', warehouse_type: 'RAW_MATERIAL' });
    await load();
  }

  return (
    <>
      <AppNav />
      <main className="pageShell">
        <div className="pageHeader">
          <div><div className="eyebrow">Master data</div><h1>Warehouses</h1><p>Define physical and logical storage areas: raw material, WIP, finished goods, scrap, quality hold.</p></div>
          <CompanySelect companies={companies} companyId={companyId} onChange={setCompanyId} />
        </div>
        <section className="twoColumn">
          <form className="formCard" onSubmit={submit}>
            <h2>New warehouse</h2>
            <label>Code<input value={form.code} onChange={(e) => setForm({ ...form, code: e.target.value })} required /></label>
            <label>Name<input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} required /></label>
            <label>Type<select value={form.warehouse_type} onChange={(e) => setForm({ ...form, warehouse_type: e.target.value })}>{types.map((type) => <option key={type}>{type}</option>)}</select></label>
            {message && <div className="formMessage">{message}</div>}
            <button className="button" disabled={!companyId}>Create warehouse</button>
          </form>
          <section className="panel">
            <h2>Warehouses list</h2>
            <div className="tableWrap"><table><thead><tr><th>Code</th><th>Name</th><th>Type</th></tr></thead><tbody>{warehouses.map((wh) => <tr key={wh.id}><td>{wh.code}</td><td>{wh.name}</td><td>{wh.warehouse_type}</td></tr>)}</tbody></table></div>
          </section>
        </section>
      </main>
    </>
  );
}
