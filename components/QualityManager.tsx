'use client';

import { FormEvent, useEffect, useMemo, useState } from 'react';
import { AppNav } from './AppNav';
import { CompanySelect, useCompany } from './useCompany';

type Item = { id: string; item_code: string; name: string };
type Warehouse = { id: string; code: string; name: string; warehouse_type: string };
type Stock = { id: string; item_id: string; warehouse_id: string; location_id?: string | null; lot_id?: string | null; quantity_on_hand: number; quantity_reserved: number; items?: { item_code: string; name: string }; warehouses?: { code: string; name: string }; lots?: { lot_number: string } | null };
type Ncr = { id: string; ncr_number: string; severity: string; status: string; description: string; disposition: string; items?: { item_code: string; name: string }; lots?: { lot_number: string } | null };
type Hold = { id: string; hold_number: string; quantity: number; remaining_qty: number; status: string; reason_code?: string | null; items?: { item_code: string; name: string }; lots?: { lot_number: string } | null; source?: { code: string; name: string }; hold?: { code: string; name: string }; nonconformance_reports?: { ncr_number: string; status: string } | null };

export function QualityManager() {
  const { companies, companyId, setCompanyId } = useCompany();
  const [items, setItems] = useState<Item[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [stock, setStock] = useState<Stock[]>([]);
  const [ncrs, setNcrs] = useState<Ncr[]>([]);
  const [holds, setHolds] = useState<Hold[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [ncrForm, setNcrForm] = useState({ ncr_number: '', item_id: '', description: '', severity: 'MEDIUM' });
  const [holdForm, setHoldForm] = useState({ hold_number: '', stock_balance_id: '', hold_warehouse_id: '', quantity: 1, ncr_id: '', reason_code: '', note: '' });

  const qualityWarehouses = useMemo(() => warehouses.filter((w) => w.warehouse_type === 'QUALITY'), [warehouses]);
  const scrapWarehouses = useMemo(() => warehouses.filter((w) => w.warehouse_type === 'SCRAP'), [warehouses]);
  const selectedStock = useMemo(() => stock.find((s) => s.id === holdForm.stock_balance_id), [stock, holdForm.stock_balance_id]);

  async function load() {
    if (!companyId) return;
    const [itemRes, whRes, stockRes, ncrRes, holdRes] = await Promise.all([
      fetch(`/api/items?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/warehouses?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/stock-balances?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/nonconformance-reports?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/quality-holds?company_id=${companyId}`).then((r) => r.json()),
    ]);
    const itemList = itemRes.data ?? [];
    const whList = whRes.data ?? [];
    const stockList = (stockRes.data ?? []).filter((s: Stock) => Number(s.quantity_on_hand) - Number(s.quantity_reserved) > 0);
    setItems(itemList);
    setWarehouses(whList);
    setStock(stockList);
    setNcrs(ncrRes.data ?? []);
    setHolds(holdRes.data ?? []);
    setNcrForm((old) => ({ ...old, item_id: old.item_id || itemList[0]?.id || '' }));
    setHoldForm((old) => ({ ...old, stock_balance_id: old.stock_balance_id || stockList[0]?.id || '', hold_warehouse_id: old.hold_warehouse_id || whList.find((w: Warehouse) => w.warehouse_type === 'QUALITY')?.id || '' }));
  }

  useEffect(() => { load(); }, [companyId]);

  async function createNcr(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    const res = await fetch('/api/nonconformance-reports', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ company_id: companyId, ...ncrForm, item_id: ncrForm.item_id || null }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage('NCR created.');
    setNcrForm({ ...ncrForm, ncr_number: '', description: '' });
    await load();
  }

  async function createHold(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    if (!selectedStock) { setMessage('Select available stock balance.'); return; }
    const res = await fetch('/api/quality-holds', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        company_id: companyId,
        hold_number: holdForm.hold_number,
        item_id: selectedStock.item_id,
        source_warehouse_id: selectedStock.warehouse_id,
        source_location_id: selectedStock.location_id ?? null,
        lot_id: selectedStock.lot_id ?? null,
        hold_warehouse_id: holdForm.hold_warehouse_id,
        quantity: Number(holdForm.quantity),
        ncr_id: holdForm.ncr_id || null,
        reason_code: holdForm.reason_code || null,
        note: holdForm.note || null,
      }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage('Quality hold created and stock moved to quarantine.');
    setHoldForm({ ...holdForm, hold_number: '', quantity: 1, note: '' });
    await load();
  }

  async function releaseHold(id: string) {
    if (!window.confirm('Release this quality hold back to available stock?')) return;
    setMessage(null);
    const res = await fetch(`/api/quality-holds/${id}/release`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ note: 'Released from quality hold' }) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Quality hold released. Transaction: ${json.transaction_id}`);
    await load();
  }

  async function scrapHold(id: string) {
    if (!window.confirm('Scrap this held stock?')) return;
    setMessage(null);
    const scrapWh = scrapWarehouses[0]?.id;
    if (!scrapWh) { setMessage('No SCRAP warehouse exists.'); return; }
    const res = await fetch(`/api/quality-holds/${id}/scrap`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ scrap_warehouse_id: scrapWh, note: 'Scrapped from quality hold' }) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Quality hold scrapped. Transaction: ${json.transaction_id}`);
    await load();
  }

  return (
    <>
      <AppNav />
      <main className="pageShell wide">
        <div className="pageHeader">
          <div><div className="eyebrow">Quality</div><h1>Quality holds & NCR</h1><p>Move stock to quarantine, create nonconformance reports, release or scrap held stock.</p></div>
          <CompanySelect companies={companies} companyId={companyId} onChange={setCompanyId} />
        </div>
        {message && <div className="formMessage">{message}</div>}

        <section className="splitPanels">
          <div className="stack">
            <form className="formCard" onSubmit={createNcr}>
              <h2>New nonconformance report</h2>
              <label>NCR number<input value={ncrForm.ncr_number} onChange={(e) => setNcrForm({ ...ncrForm, ncr_number: e.target.value })} required placeholder="NCR-2026-0001" /></label>
              <label>Item<select value={ncrForm.item_id} onChange={(e) => setNcrForm({ ...ncrForm, item_id: e.target.value })}><option value="">None</option>{items.map((i) => <option key={i.id} value={i.id}>{i.item_code} - {i.name}</option>)}</select></label>
              <label>Severity<select value={ncrForm.severity} onChange={(e) => setNcrForm({ ...ncrForm, severity: e.target.value })}><option>LOW</option><option>MEDIUM</option><option>HIGH</option><option>CRITICAL</option></select></label>
              <label>Description<textarea value={ncrForm.description} onChange={(e) => setNcrForm({ ...ncrForm, description: e.target.value })} required /></label>
              <button className="button" disabled={!companyId}>Create NCR</button>
            </form>

            <form className="formCard" onSubmit={createHold}>
              <h2>New quality hold</h2>
              <label>Hold number<input value={holdForm.hold_number} onChange={(e) => setHoldForm({ ...holdForm, hold_number: e.target.value })} required placeholder="QH-2026-0001" /></label>
              <label>Available stock<select value={holdForm.stock_balance_id} onChange={(e) => setHoldForm({ ...holdForm, stock_balance_id: e.target.value })} required>{stock.map((s) => <option key={s.id} value={s.id}>{s.items?.item_code} · {s.warehouses?.code} · lot {s.lots?.lot_number ?? '-'} · avail {Number(s.quantity_on_hand) - Number(s.quantity_reserved)}</option>)}</select></label>
              <label>Quality warehouse<select value={holdForm.hold_warehouse_id} onChange={(e) => setHoldForm({ ...holdForm, hold_warehouse_id: e.target.value })} required>{qualityWarehouses.map((w) => <option key={w.id} value={w.id}>{w.code} - {w.name}</option>)}</select></label>
              <label>Quantity<input type="number" min="0.0001" step="0.0001" value={holdForm.quantity} onChange={(e) => setHoldForm({ ...holdForm, quantity: Number(e.target.value) })} required /></label>
              <label>NCR<select value={holdForm.ncr_id} onChange={(e) => setHoldForm({ ...holdForm, ncr_id: e.target.value })}><option value="">None</option>{ncrs.map((n) => <option key={n.id} value={n.id}>{n.ncr_number} - {n.status}</option>)}</select></label>
              <label>Reason<input value={holdForm.reason_code} onChange={(e) => setHoldForm({ ...holdForm, reason_code: e.target.value })} placeholder="inspection / complaint / quarantine" /></label>
              <label>Note<textarea value={holdForm.note} onChange={(e) => setHoldForm({ ...holdForm, note: e.target.value })} /></label>
              <button className="button" disabled={!companyId || !qualityWarehouses.length || !stock.length}>Create hold</button>
            </form>
          </div>

          <div className="stack">
            <section className="panel">
              <h2>Quality holds</h2>
              <div className="tableWrap"><table><thead><tr><th>Hold</th><th>Item</th><th>Lot</th><th>Source</th><th>Hold wh</th><th>Qty</th><th>Remaining</th><th>Status</th><th></th></tr></thead><tbody>{holds.map((h) => <tr key={h.id}><td>{h.hold_number}</td><td>{h.items?.item_code}</td><td>{h.lots?.lot_number ?? ''}</td><td>{h.source?.code}</td><td>{h.hold?.code}</td><td>{h.quantity}</td><td>{h.remaining_qty}</td><td><span className="badge">{h.status}</span></td><td><div className="opButtons"><button className="button small secondary" disabled={Number(h.remaining_qty) <= 0} onClick={() => releaseHold(h.id)}>Release</button><button className="button small secondary" disabled={Number(h.remaining_qty) <= 0 || !scrapWarehouses.length} onClick={() => scrapHold(h.id)}>Scrap</button></div></td></tr>)}</tbody></table></div>
            </section>
            <section className="panel">
              <h2>Nonconformance reports</h2>
              <div className="tableWrap"><table><thead><tr><th>NCR</th><th>Severity</th><th>Status</th><th>Item</th><th>Disposition</th><th>Description</th></tr></thead><tbody>{ncrs.map((n) => <tr key={n.id}><td>{n.ncr_number}</td><td>{n.severity}</td><td><span className="badge">{n.status}</span></td><td>{n.items?.item_code}</td><td>{n.disposition}</td><td>{n.description}</td></tr>)}</tbody></table></div>
            </section>
          </div>
        </section>
      </main>
    </>
  );
}
