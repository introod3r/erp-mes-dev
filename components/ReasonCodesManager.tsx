'use client';

import { FormEvent, useEffect, useState } from 'react';
import { AppNav } from './AppNav';
import { CompanySelect, useCompany } from './useCompany';

type Reason = { id: string; code: string; name: string; category?: string | null; is_active: boolean };

export function ReasonCodesManager() {
  const { companies, companyId, setCompanyId } = useCompany();
  const [scrap, setScrap] = useState<Reason[]>([]);
  const [downtime, setDowntime] = useState<Reason[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [scrapForm, setScrapForm] = useState({ code: '', name: '', category: '' });
  const [downForm, setDownForm] = useState({ code: '', name: '', category: '' });

  async function load() {
    if (!companyId) return;
    const [s, d] = await Promise.all([
      fetch(`/api/scrap-reasons?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/downtime-reasons?company_id=${companyId}`).then((r) => r.json()),
    ]);
    setScrap(s.data ?? []);
    setDowntime(d.data ?? []);
  }

  useEffect(() => { load(); }, [companyId]);

  async function seed() {
    setMessage(null);
    const res = await fetch('/api/reason-codes/seed', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ company_id: companyId }) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage('Default reason codes seeded.');
    await load();
  }

  async function createScrap(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    const res = await fetch('/api/scrap-reasons', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ company_id: companyId, ...scrapForm, category: scrapForm.category || null }) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error?.message ?? JSON.stringify(json.error)); return; }
    setScrapForm({ code: '', name: '', category: '' });
    await load();
  }

  async function createDowntime(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    const res = await fetch('/api/downtime-reasons', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ company_id: companyId, ...downForm, category: downForm.category || null }) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error?.message ?? JSON.stringify(json.error)); return; }
    setDownForm({ code: '', name: '', category: '' });
    await load();
  }

  return (
    <>
      <AppNav />
      <main className="pageShell">
        <div className="pageHeader">
          <div>
            <div className="eyebrow">Quality / MES master data</div>
            <h1>Reason codes</h1>
            <p>Structured reasons for scrap and downtime. Avoid free-text-only production reporting.</p>
          </div>
          <div className="headerActions"><CompanySelect companies={companies} companyId={companyId} onChange={setCompanyId} /><button className="button" disabled={!companyId} onClick={seed}>Seed defaults</button></div>
        </div>

        {message && <div className="formMessage">{message}</div>}

        <section className="splitPanels">
          <div className="stack">
            <form className="formCard" onSubmit={createScrap}>
              <h2>New scrap reason</h2>
              <label>Code<input value={scrapForm.code} onChange={(e) => setScrapForm({ ...scrapForm, code: e.target.value })} required placeholder="DIM_NOK" /></label>
              <label>Name<input value={scrapForm.name} onChange={(e) => setScrapForm({ ...scrapForm, name: e.target.value })} required placeholder="Dimension out of tolerance" /></label>
              <label>Category<input value={scrapForm.category} onChange={(e) => setScrapForm({ ...scrapForm, category: e.target.value })} placeholder="QUALITY" /></label>
              <button className="button" disabled={!companyId}>Create scrap reason</button>
            </form>
            <section className="panel">
              <h2>Scrap reasons</h2>
              <div className="tableWrap"><table><thead><tr><th>Code</th><th>Name</th><th>Category</th></tr></thead><tbody>{scrap.map((r) => <tr key={r.id}><td>{r.code}</td><td>{r.name}</td><td>{r.category}</td></tr>)}</tbody></table></div>
            </section>
          </div>

          <div className="stack">
            <form className="formCard" onSubmit={createDowntime}>
              <h2>New downtime reason</h2>
              <label>Code<input value={downForm.code} onChange={(e) => setDownForm({ ...downForm, code: e.target.value })} required placeholder="MACHINE_DOWN" /></label>
              <label>Name<input value={downForm.name} onChange={(e) => setDownForm({ ...downForm, name: e.target.value })} required placeholder="Machine breakdown" /></label>
              <label>Category<input value={downForm.category} onChange={(e) => setDownForm({ ...downForm, category: e.target.value })} placeholder="MACHINE" /></label>
              <button className="button" disabled={!companyId}>Create downtime reason</button>
            </form>
            <section className="panel">
              <h2>Downtime reasons</h2>
              <div className="tableWrap"><table><thead><tr><th>Code</th><th>Name</th><th>Category</th></tr></thead><tbody>{downtime.map((r) => <tr key={r.id}><td>{r.code}</td><td>{r.name}</td><td>{r.category}</td></tr>)}</tbody></table></div>
            </section>
          </div>
        </section>
      </main>
    </>
  );
}
