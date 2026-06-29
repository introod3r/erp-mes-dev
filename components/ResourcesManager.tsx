'use client';

import { FormEvent, useEffect, useState } from 'react';
import { AppNav } from './AppNav';
import { CompanySelect, useCompany } from './useCompany';

type WorkCenter = { id: string; code: string; name: string; department?: string | null };
type Machine = { id: string; code: string; name: string; machine_type?: string | null; status: string; work_centers?: { code: string; name: string } };

export function ResourcesManager() {
  const { companies, companyId, setCompanyId } = useCompany();
  const [workCenters, setWorkCenters] = useState<WorkCenter[]>([]);
  const [machines, setMachines] = useState<Machine[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [wcForm, setWcForm] = useState({ code: '', name: '', department: '' });
  const [machineForm, setMachineForm] = useState({ code: '', name: '', machine_type: '', work_center_id: '', status: 'AVAILABLE' });

  async function load() {
    if (!companyId) return;
    const [wcRes, machineRes] = await Promise.all([
      fetch(`/api/work-centers?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/machines?company_id=${companyId}`).then((r) => r.json()),
    ]);
    const wcs = wcRes.data ?? [];
    setWorkCenters(wcs);
    setMachines(machineRes.data ?? []);
    setMachineForm((old) => ({ ...old, work_center_id: old.work_center_id || wcs[0]?.id || '' }));
  }

  useEffect(() => { load(); }, [companyId]);

  async function createWorkCenter(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    const res = await fetch('/api/work-centers', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ company_id: companyId, ...wcForm, department: wcForm.department || null }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error?.message ?? JSON.stringify(json.error)); return; }
    setWcForm({ code: '', name: '', department: '' });
    await load();
  }

  async function createMachine(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    const res = await fetch('/api/machines', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ company_id: companyId, ...machineForm, machine_type: machineForm.machine_type || null }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error?.message ?? JSON.stringify(json.error)); return; }
    setMachineForm({ ...machineForm, code: '', name: '', machine_type: '' });
    await load();
  }

  return (
    <>
      <AppNav />
      <main className="pageShell">
        <div className="pageHeader">
          <div>
            <div className="eyebrow">Manufacturing resources</div>
            <h1>Work centers & machines</h1>
            <p>Define production capacity before creating routings.</p>
          </div>
          <CompanySelect companies={companies} companyId={companyId} onChange={setCompanyId} />
        </div>

        {message && <div className="formMessage">{message}</div>}

        <section className="twoColumn">
          <div className="stack">
            <form className="formCard" onSubmit={createWorkCenter}>
              <h2>New work center</h2>
              <label>Code<input value={wcForm.code} onChange={(e) => setWcForm({ ...wcForm, code: e.target.value })} required placeholder="STAMP" /></label>
              <label>Name<input value={wcForm.name} onChange={(e) => setWcForm({ ...wcForm, name: e.target.value })} required placeholder="Stamping" /></label>
              <label>Department<input value={wcForm.department} onChange={(e) => setWcForm({ ...wcForm, department: e.target.value })} placeholder="Production" /></label>
              <button className="button" disabled={!companyId}>Create work center</button>
            </form>

            <form className="formCard" onSubmit={createMachine}>
              <h2>New machine</h2>
              <label>Work center<select value={machineForm.work_center_id} onChange={(e) => setMachineForm({ ...machineForm, work_center_id: e.target.value })} required>{workCenters.map((wc) => <option key={wc.id} value={wc.id}>{wc.code} - {wc.name}</option>)}</select></label>
              <label>Code<input value={machineForm.code} onChange={(e) => setMachineForm({ ...machineForm, code: e.target.value })} required placeholder="PRESS-01" /></label>
              <label>Name<input value={machineForm.name} onChange={(e) => setMachineForm({ ...machineForm, name: e.target.value })} required placeholder="Mechanical press 01" /></label>
              <label>Machine type<input value={machineForm.machine_type} onChange={(e) => setMachineForm({ ...machineForm, machine_type: e.target.value })} placeholder="Press / CNC / Plating line" /></label>
              <button className="button" disabled={!companyId || !workCenters.length}>Create machine</button>
            </form>
          </div>

          <div className="stack">
            <section className="panel">
              <h2>Work centers</h2>
              <div className="tableWrap"><table><thead><tr><th>Code</th><th>Name</th><th>Department</th></tr></thead><tbody>{workCenters.map((wc) => <tr key={wc.id}><td>{wc.code}</td><td>{wc.name}</td><td>{wc.department}</td></tr>)}</tbody></table></div>
            </section>
            <section className="panel">
              <h2>Machines</h2>
              <div className="tableWrap"><table><thead><tr><th>Code</th><th>Name</th><th>Work center</th><th>Status</th></tr></thead><tbody>{machines.map((m) => <tr key={m.id}><td>{m.code}</td><td>{m.name}</td><td>{m.work_centers?.code}</td><td><span className="badge">{m.status}</span></td></tr>)}</tbody></table></div>
            </section>
          </div>
        </section>
      </main>
    </>
  );
}
