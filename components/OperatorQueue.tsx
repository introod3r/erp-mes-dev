'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { AppNav } from './AppNav';
import { CompanySelect, useCompany } from './useCompany';

type WorkCenter = { id: string; code: string; name: string };
type QueueRow = {
  id: string;
  sequence_no: number;
  operation_code: string;
  operation_name: string;
  status: string;
  planned_quantity: number;
  completed_quantity: number;
  scrap_quantity: number;
  production_orders?: { id: string; order_number: string; status: string; items?: { item_code: string; name: string } };
  work_centers?: { code: string; name: string };
};

export function OperatorQueue() {
  const { companies, companyId, setCompanyId } = useCompany();
  const [workCenters, setWorkCenters] = useState<WorkCenter[]>([]);
  const [workCenterId, setWorkCenterId] = useState('');
  const [queue, setQueue] = useState<QueueRow[]>([]);
  const [barcode, setBarcode] = useState('');
  const [message, setMessage] = useState<string | null>(null);

  async function load() {
    if (!companyId) return;
    const [wcRes, queueRes] = await Promise.all([
      fetch(`/api/work-centers?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/operator-queue?company_id=${companyId}${workCenterId ? `&work_center_id=${workCenterId}` : ''}`).then((r) => r.json()),
    ]);
    setWorkCenters(wcRes.data ?? []);
    setQueue(queueRes.data ?? []);
  }

  useEffect(() => { load(); }, [companyId, workCenterId]);

  function openByBarcode() {
    const q = barcode.trim().toLowerCase();
    const found = queue.find((row) => row.production_orders?.order_number.toLowerCase() === q || row.operation_code.toLowerCase() === q || row.id.toLowerCase() === q);
    if (found?.production_orders?.id) window.location.href = `/production-orders/${found.production_orders.id}`;
    else setMessage('No queue item matches barcode/search.');
  }

  async function action(id: string, actionName: 'start' | 'pause' | 'stop') {
    setMessage(null);
    const res = await fetch(`/api/production-order-operations/${id}/${actionName}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    await load();
  }

  return (
    <>
      <AppNav />
      <main className="pageShell wide">
        <div className="pageHeader">
          <div>
            <div className="eyebrow">Shop floor</div>
            <h1>Operator queue</h1>
            <p>Simplified work queue for READY, IN_PROGRESS and PAUSED operations.</p>
          </div>
          <div className="headerActions"><CompanySelect companies={companies} companyId={companyId} onChange={setCompanyId} /><label className="companySelect">Work center<select value={workCenterId} onChange={(e) => setWorkCenterId(e.target.value)}><option value="">All</option>{workCenters.map((wc) => <option key={wc.id} value={wc.id}>{wc.code} - {wc.name}</option>)}</select></label></div>
        </div>

        {message && <div className="formMessage">{message}</div>}
        <section className="panel operatorSearch"><label>Barcode / order / operation search<input value={barcode} onChange={(e) => setBarcode(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') openByBarcode(); }} placeholder="Scan or type order number" autoFocus /></label><button className="button" onClick={openByBarcode}>Open</button></section>

        <section className="queueGrid">
          {queue.map((row) => (
            <article className="queueCard" key={row.id}>
              <div className="queueTop"><span className="badge big">{row.status}</span><span>{row.work_centers?.code}</span></div>
              <h2>{row.operation_code} — {row.operation_name}</h2>
              <p><b>{row.production_orders?.order_number}</b> · {row.production_orders?.items?.item_code} · Seq {row.sequence_no}</p>
              <div className="miniStats"><span>Plan: <b>{row.planned_quantity}</b></span><span>Good: <b>{row.completed_quantity}</b></span><span>Scrap: <b>{row.scrap_quantity}</b></span></div>
              <div className="queueActions">
                <button className="button" disabled={row.status === 'IN_PROGRESS'} onClick={() => action(row.id, 'start')}>{row.status === 'PAUSED' ? 'Resume' : 'Start'}</button>
                <button className="button secondary" disabled={row.status !== 'IN_PROGRESS'} onClick={() => action(row.id, 'pause')}>Pause</button>
                <button className="button secondary" disabled={!['IN_PROGRESS','PAUSED'].includes(row.status)} onClick={() => action(row.id, 'stop')}>Stop</button>
                <Link className="button secondary" href={`/production-orders/${row.production_orders?.id}`}>Open order</Link>
              </div>
            </article>
          ))}
          {!queue.length && <section className="panel">No operations in queue.</section>}
        </section>
      </main>
    </>
  );
}
