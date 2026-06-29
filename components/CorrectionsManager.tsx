'use client';

import { FormEvent, useEffect, useState } from 'react';
import { AppNav } from './AppNav';
import { CompanySelect, useCompany } from './useCompany';

type Correction = { id: string; request_number: string; correction_type: string; target_id: string; reason: string; status: string; requested_at: string; result_reference_id?: string | null };

export function CorrectionsManager() {
  const { companies, companyId, setCompanyId } = useCompany();
  const [rows, setRows] = useState<Correction[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [form, setForm] = useState({ request_number: '', correction_type: 'PRODUCTION_CONSUMPTION', target_id: '', reason: '' });

  async function load() {
    if (!companyId) return;
    const json = await fetch(`/api/correction-requests?company_id=${companyId}`).then((r) => r.json());
    setRows(json.data ?? []);
  }
  useEffect(() => { load(); }, [companyId]);

  async function submit(e: FormEvent) {
    e.preventDefault(); setMessage(null);
    const res = await fetch('/api/correction-requests', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ company_id: companyId, ...form }) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage('Correction request created.'); setForm({ ...form, request_number: '', target_id: '', reason: '' }); await load();
  }
  async function review(id: string, approve: boolean) { const res = await fetch(`/api/correction-requests/${id}/review`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ approve, review_note: approve ? 'Approved' : 'Rejected' }) }); const json = await res.json(); if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; } await load(); }
  async function execute(id: string) { if (!window.confirm('Execute approved correction?')) return; const res = await fetch(`/api/correction-requests/${id}/execute`, { method: 'POST' }); const json = await res.json(); if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; } setMessage(`Correction executed: ${json.result_reference_id}`); await load(); }

  return <><AppNav /><main className="pageShell wide"><div className="pageHeader"><div><div className="eyebrow">Controls</div><h1>Correction approvals</h1><p>Request, approve and execute controlled corrections instead of direct reversal.</p></div><CompanySelect companies={companies} companyId={companyId} onChange={setCompanyId} /></div>{message && <div className="formMessage">{message}</div>}<section className="splitPanels"><form className="formCard" onSubmit={submit}><h2>New correction request</h2><label>Request number<input value={form.request_number} onChange={(e)=>setForm({...form,request_number:e.target.value})} required placeholder="COR-2026-0001" /></label><label>Type<select value={form.correction_type} onChange={(e)=>setForm({...form,correction_type:e.target.value})}><option>INVENTORY_TRANSACTION</option><option>PRODUCTION_CONSUMPTION</option><option>PRODUCTION_RECEIPT</option><option>OPERATION_EVENT</option></select></label><label>Target ID<input value={form.target_id} onChange={(e)=>setForm({...form,target_id:e.target.value})} required placeholder="uuid" /></label><label>Reason<textarea value={form.reason} onChange={(e)=>setForm({...form,reason:e.target.value})} required /></label><button className="button" disabled={!companyId}>Create request</button></form><section className="panel"><h2>Requests</h2><div className="tableWrap"><table><thead><tr><th>No</th><th>Type</th><th>Target</th><th>Status</th><th>Reason</th><th></th></tr></thead><tbody>{rows.map((r)=><tr key={r.id}><td>{r.request_number}</td><td>{r.correction_type}</td><td>{r.target_id.slice(0,8)}...</td><td><span className="badge">{r.status}</span></td><td>{r.reason}</td><td><div className="opButtons"><button className="button small secondary" disabled={r.status!=='REQUESTED'} onClick={()=>review(r.id,true)}>Approve</button><button className="button small secondary" disabled={r.status!=='REQUESTED'} onClick={()=>review(r.id,false)}>Reject</button><button className="button small" disabled={r.status!=='APPROVED'} onClick={()=>execute(r.id)}>Execute</button></div></td></tr>)}</tbody></table></div></section></section></main></>;
}
