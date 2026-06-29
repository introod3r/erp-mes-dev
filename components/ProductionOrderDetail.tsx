'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { AppNav } from './AppNav';

type Order = {
  id: string;
  company_id: string;
  order_number: string;
  status: string;
  planned_quantity: number;
  produced_quantity: number;
  scrap_quantity: number;
  items?: { item_code: string; name: string };
  units_of_measure?: { code: string; symbol: string };
};

type Material = {
  id: string;
  planned_qty: number;
  reserved_qty: number;
  issued_qty: number;
  consumed_qty: number;
  issue_method: string;
  operation_sequence?: number | null;
  items?: { item_code: string; name: string };
  units_of_measure?: { code: string; symbol: string };
};

type Operation = {
  id: string;
  sequence_no: number;
  operation_code: string;
  operation_name: string;
  planned_setup_time_minutes: number;
  planned_run_time_minutes: number;
  completed_quantity: number;
  scrap_quantity: number;
  status: string;
  work_centers?: { code: string; name: string };
};

type Availability = {
  production_order_material_id: string;
  item_id: string;
  item_code: string;
  item_name: string;
  planned_qty: number;
  reserved_qty: number;
  consumed_qty: number;
  uom_code: string;
  quantity_on_hand: number;
  quantity_reserved_total: number;
  quantity_available: number;
  remaining_to_reserve: number;
  shortage_qty: number;
};

type Warehouse = { id: string; code: string; name: string; warehouse_type: string };
type Reason = { id: string; code: string; name: string; category?: string | null };
type OperationEvent = { id: string; event_type: string; event_time: string; quantity_good: number; quantity_scrap: number; reason_code?: string | null; note?: string | null; is_reversed?: boolean; production_order_operations?: { sequence_no: number; operation_code: string; operation_name: string }; machines?: { code: string; name: string } | null };
type Reservation = { id: string; reserved_qty: number; consumed_qty: number; released_qty: number; status: string; created_at: string; items?: { item_code: string; name: string }; warehouses?: { code: string; name: string }; lots?: { lot_number: string } | null };
type Consumption = { id: string; quantity: number; consumed_at: string; is_reversed: boolean; items?: { item_code: string; name: string }; warehouses?: { code: string; name: string }; lots?: { lot_number: string } | null };
type Receipt = { id: string; quantity_good: number; quantity_scrap: number; received_at: string; is_reversed: boolean; items?: { item_code: string; name: string }; warehouses?: { code: string; name: string }; lots?: { lot_number: string } | null };
type StockBalance = { id: string; item_id: string; warehouse_id: string; location_id?: string | null; lot_id?: string | null; quantity_on_hand: number; quantity_reserved: number; warehouses?: { code: string; name: string }; lots?: { lot_number: string } | null };

export function ProductionOrderDetail({ id }: { id: string }) {
  const [order, setOrder] = useState<Order | null>(null);
  const [materials, setMaterials] = useState<Material[]>([]);
  const [operations, setOperations] = useState<Operation[]>([]);
  const [availability, setAvailability] = useState<Availability[]>([]);
  const [warehouses, setWarehouses] = useState<Warehouse[]>([]);
  const [stockBalances, setStockBalances] = useState<StockBalance[]>([]);
  const [manualReserve, setManualReserve] = useState<Record<string, { stock_balance_id: string; quantity: number }>>({});
  const [scrapReasons, setScrapReasons] = useState<Reason[]>([]);
  const [downtimeReasons, setDowntimeReasons] = useState<Reason[]>([]);
  const [events, setEvents] = useState<OperationEvent[]>([]);
  const [reservations, setReservations] = useState<Reservation[]>([]);
  const [consumptions, setConsumptions] = useState<Consumption[]>([]);
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [consumeQty, setConsumeQty] = useState<Record<string, number>>({});
  const [operationReport, setOperationReport] = useState<Record<string, { good: number; scrap: number; reason: string; note: string }>>({});
  const [receipt, setReceipt] = useState({ warehouse_id: '', scrap_warehouse_id: '', quantity_good: 0, quantity_scrap: 0, lot_number: '', finish_order: false });
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  async function load() {
    setLoading(true);
    setMessage(null);
    const [orderRes, materialRes, operationRes, availabilityRes, eventRes, reservationRes, consumptionRes, receiptRes] = await Promise.all([
      fetch(`/api/production-orders/${id}`).then((r) => r.json()),
      fetch(`/api/production-orders/${id}/materials`).then((r) => r.json()),
      fetch(`/api/production-orders/${id}/operations`).then((r) => r.json()),
      fetch(`/api/production-orders/${id}/availability`).then((r) => r.json()),
      fetch(`/api/production-orders/${id}/operation-events`).then((r) => r.json()),
      fetch(`/api/production-orders/${id}/reservations`).then((r) => r.json()),
      fetch(`/api/production-orders/${id}/consumptions`).then((r) => r.json()),
      fetch(`/api/production-orders/${id}/receipts`).then((r) => r.json()),
    ]);
    if (orderRes.error) setMessage(orderRes.error);
    setOrder(orderRes.data ?? null);
    setMaterials(materialRes.data ?? []);
    setOperations(operationRes.data ?? []);
    setAvailability(availabilityRes.data ?? []);
    setEvents(eventRes.data ?? []);
    setReservations(reservationRes.data ?? []);
    setConsumptions(consumptionRes.data ?? []);
    setReceipts(receiptRes.data ?? []);

    if (orderRes.data?.company_id) {
      const [whRes, stockRes, scrapRes, downRes] = await Promise.all([
        fetch(`/api/warehouses?company_id=${orderRes.data.company_id}`).then((r) => r.json()),
        fetch(`/api/stock-balances?company_id=${orderRes.data.company_id}`).then((r) => r.json()),
        fetch(`/api/scrap-reasons?company_id=${orderRes.data.company_id}`).then((r) => r.json()),
        fetch(`/api/downtime-reasons?company_id=${orderRes.data.company_id}`).then((r) => r.json()),
      ]);
      const whList = whRes.data ?? [];
      setWarehouses(whList);
      setStockBalances(stockRes.data ?? []);
      setScrapReasons(scrapRes.data ?? []);
      setDowntimeReasons(downRes.data ?? []);
      setReceipt((old) => ({
        ...old,
        warehouse_id: old.warehouse_id || whList.find((w: Warehouse) => w.warehouse_type === 'FINISHED_GOODS')?.id || whList[0]?.id || '',
        scrap_warehouse_id: old.scrap_warehouse_id || whList.find((w: Warehouse) => w.warehouse_type === 'SCRAP')?.id || '',
      }));
    }

    setLoading(false);
  }

  useEffect(() => { load(); }, [id]);

  async function release() {
    setMessage(null);
    const res = await fetch('/api/production-orders/release', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ production_order_id: id }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    await load();
  }

  async function backflushOrder() {
    if (!window.confirm('Backflush all remaining BACKFLUSH materials for this order?')) return;
    setMessage(null);
    const res = await fetch(`/api/production-orders/${id}/backflush`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({}) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Backflushed ${Number(json.consumed_qty ?? 0).toFixed(4)} material units.`);
    await load();
  }

  async function reserveAvailableMaterials() {
    setMessage(null);
    const res = await fetch(`/api/production-orders/${id}/reserve`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    const reserved = (json.data ?? []).reduce((sum: number, row: any) => sum + Number(row.reserved_now_qty ?? 0), 0);
    setMessage(`Reserved ${reserved.toFixed(4)} units across available materials.`);
    await load();
  }

  async function reserveSpecificMaterial(materialId: string) {
    setMessage(null);
    const choice = manualReserve[materialId];
    const balance = stockBalances.find((s) => s.id === choice?.stock_balance_id);
    if (!choice || !balance) { setMessage('Select a stock balance for manual reservation.'); return; }
    const res = await fetch(`/api/production-order-materials/${materialId}/reserve`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        warehouse_id: balance.warehouse_id,
        location_id: balance.location_id ?? null,
        lot_id: balance.lot_id ?? null,
        quantity: Number(choice.quantity || 0) || null,
      }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Manual reservation created: ${json.reservation_id}`);
    await load();
  }

  async function releaseAllReservations() {
    if (!window.confirm('Release all unused reservations for this order?')) return;
    setMessage(null);
    const res = await fetch(`/api/production-orders/${id}/release-reservations`, { method: 'POST' });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Released ${Number(json.released_qty ?? 0).toFixed(4)} reserved units.`);
    await load();
  }

  async function releaseReservation(reservationId: string) {
    if (!window.confirm('Release this reservation?')) return;
    setMessage(null);
    const res = await fetch(`/api/inventory-reservations/${reservationId}/release`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({})
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Released ${Number(json.released_qty ?? 0).toFixed(4)} reserved units.`);
    await load();
  }

  async function consumeMaterial(materialId: string) {
    setMessage(null);
    const quantity = Number(consumeQty[materialId] ?? 0);
    if (quantity <= 0) { setMessage('Consumption quantity must be positive.'); return; }
    const res = await fetch(`/api/production-order-materials/${materialId}/consume`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ quantity }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Material consumed. Transaction: ${json.transaction_id}`);
    setConsumeQty((old) => ({ ...old, [materialId]: 0 }));
    await load();
  }

  async function receiveGoods() {
    setMessage(null);
    const res = await fetch(`/api/production-orders/${id}/receive`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        warehouse_id: receipt.warehouse_id,
        quantity_good: Number(receipt.quantity_good),
        quantity_scrap: Number(receipt.quantity_scrap),
        scrap_warehouse_id: receipt.scrap_warehouse_id || null,
        lot_number: receipt.lot_number || null,
        finish_order: receipt.finish_order,
      }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Finished goods received. Transaction: ${json.transaction_id}`);
    setReceipt({ ...receipt, quantity_good: 0, quantity_scrap: 0, lot_number: '', finish_order: false });
    await load();
  }

  async function reverseConsumption(consumptionId: string) {
    if (!window.confirm('Reverse this material consumption? This will create correction ledger entries.')) return;
    setMessage(null);
    const res = await fetch(`/api/production-consumptions/${consumptionId}/reverse`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ note: 'UI correction' }) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Consumption reversed. Transaction: ${json.reversal_transaction_id}`);
    await load();
  }

  async function reverseReceipt(receiptId: string) {
    if (!window.confirm('Reverse this production receipt? Stock must still be available.')) return;
    setMessage(null);
    const res = await fetch(`/api/production-receipts/${receiptId}/reverse`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ note: 'UI correction' }) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Receipt reversed. Transaction: ${json.reversal_transaction_id}`);
    await load();
  }

  async function reverseOperationEvent(eventId: string) {
    if (!window.confirm('Reverse this operation event?')) return;
    setMessage(null);
    const res = await fetch(`/api/operation-events/${eventId}/reverse`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ note: 'UI correction' }) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage('Operation event reversed.');
    await load();
  }

  async function operationAction(operationId: string, action: 'start' | 'pause' | 'stop') {
    setMessage(null);
    const res = await fetch(`/api/production-order-operations/${operationId}/${action}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(`Operation ${action} recorded.`);
    await load();
  }

  async function reportOperation(operationId: string, complete = false) {
    setMessage(null);
    const values = operationReport[operationId] ?? { good: 0, scrap: 0, reason: '', note: '' };
    const res = await fetch(`/api/production-order-operations/${operationId}/report`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        quantity_good: Number(values.good || 0),
        quantity_scrap: Number(values.scrap || 0),
        reason_code: values.reason || null,
        note: values.note || null,
        complete,
      }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error ?? JSON.stringify(json)); return; }
    setMessage(complete ? 'Operation completed.' : 'Operation quantity reported.');
    setOperationReport((old) => ({ ...old, [operationId]: { good: 0, scrap: 0, reason: '', note: '' } }));
    await load();
  }

  const plannedMaterials = materials.reduce((sum, m) => sum + Number(m.planned_qty ?? 0), 0);
  const consumedMaterials = materials.reduce((sum, m) => sum + Number(m.consumed_qty ?? 0), 0);

  return (
    <>
      <AppNav />
      <main className="pageShell wide">
        <div className="pageHeader">
          <div>
            <Link href="/production-orders" className="backLink">← Production orders</Link>
            <div className="eyebrow">Production order detail</div>
            <h1>{order?.order_number ?? 'Production order'}</h1>
            <p>{order?.items?.item_code} — {order?.items?.name}</p>
          </div>
          <div className="headerActions">
            {order?.status === 'PLANNED' && <button className="button" onClick={release}>Release order</button>}
            {order && ['RELEASED', 'IN_PROGRESS'].includes(order.status) && <button className="button" onClick={reserveAvailableMaterials}>Reserve available materials</button>}
            {order && ['RELEASED', 'IN_PROGRESS'].includes(order.status) && <button className="button secondary" onClick={releaseAllReservations}>Release reservations</button>}
            {order && ['RELEASED', 'IN_PROGRESS'].includes(order.status) && <button className="button secondary" onClick={backflushOrder}>Backflush</button>}
          </div>
        </div>

        {loading && <section className="panel">Loading...</section>}
        {message && <div className="formMessage">{message}</div>}

        {order && (
          <>
            <section className="grid">
              <section className="card"><div className="cardTitle">Status</div><div className="cardValue"><span className="badge big">{order.status}</span></div><div className="cardDetail">Workflow state</div></section>
              <section className="card"><div className="cardTitle">Planned qty</div><div className="cardValue">{order.planned_quantity}</div><div className="cardDetail">{order.units_of_measure?.code}</div></section>
              <section className="card"><div className="cardTitle">Produced</div><div className="cardValue">{order.produced_quantity}</div><div className="cardDetail">Good quantity received</div></section>
              <section className="card"><div className="cardTitle">Scrap</div><div className="cardValue">{order.scrap_quantity}</div><div className="cardDetail">Reported waste</div></section>
            </section>

            <section className="splitPanels withTopMargin">
              <section className="panel">
                <h2>Material requirements & availability</h2>
                <p>Snapshot created at release. Availability is calculated from current stock balances.</p>
                <div className="miniStats"><span>Planned total: <b>{plannedMaterials.toFixed(4)}</b></span><span>Consumed total: <b>{consumedMaterials.toFixed(4)}</b></span></div>
                <div className="tableWrap"><table><thead><tr><th>Item</th><th>Planned</th><th>Reserved</th><th>Consumed</th><th>On hand</th><th>Available</th><th>Shortage</th><th>UOM</th><th>Manual reserve</th><th>Consume</th></tr></thead><tbody>{availability.map((m) => { const remainingReserved = Number(m.reserved_qty) - Number(m.consumed_qty); const balances = stockBalances.filter((s) => s.item_id === m.item_id && Number(s.quantity_on_hand) - Number(s.quantity_reserved) > 0); const choice = manualReserve[m.production_order_material_id] ?? { stock_balance_id: '', quantity: Math.max(Number(m.planned_qty) - Number(m.reserved_qty), 0) }; return <tr key={m.production_order_material_id}><td>{m.item_code} - {m.item_name}</td><td>{m.planned_qty}</td><td>{m.reserved_qty}</td><td>{m.consumed_qty}</td><td>{m.quantity_on_hand}</td><td>{m.quantity_available}</td><td className={Number(m.shortage_qty) > 0 ? 'dangerText' : 'okText'}>{m.shortage_qty}</td><td>{m.uom_code}</td><td><div className="manualReserve"><select value={choice.stock_balance_id} onChange={(e) => setManualReserve({ ...manualReserve, [m.production_order_material_id]: { ...choice, stock_balance_id: e.target.value } })}><option value="">Stock/lot</option>{balances.map((b) => <option key={b.id} value={b.id}>{b.warehouses?.code} · lot {b.lots?.lot_number ?? '-'} · avail {Number(b.quantity_on_hand) - Number(b.quantity_reserved)}</option>)}</select><input type="number" min="0" step="0.0001" value={choice.quantity} onChange={(e) => setManualReserve({ ...manualReserve, [m.production_order_material_id]: { ...choice, quantity: Number(e.target.value) } })} /><button className="button small secondary" disabled={!choice.stock_balance_id || order.status === 'FINISHED'} onClick={() => reserveSpecificMaterial(m.production_order_material_id)}>Reserve</button></div></td><td><div className="inlineAction"><input type="number" min="0" step="0.0001" max={remainingReserved} value={consumeQty[m.production_order_material_id] ?? 0} onChange={(e) => setConsumeQty({ ...consumeQty, [m.production_order_material_id]: Number(e.target.value) })} /><button className="button small" disabled={remainingReserved <= 0 || order.status === 'FINISHED'} onClick={() => consumeMaterial(m.production_order_material_id)}>Issue</button></div></td></tr>; })}</tbody></table></div>
                {!availability.length && <p className="warning">No material snapshot yet. Release the order after BOM exists.</p>}
              </section>

              <section className="panel">
                <h2>Reservations</h2>
                <p>Reserved stock allocations. Releasing a reservation makes stock available again without deleting audit history.</p>
                <div className="tableWrap"><table><thead><tr><th>Item</th><th>Warehouse</th><th>Lot</th><th>Reserved</th><th>Consumed</th><th>Released</th><th>Status</th><th></th></tr></thead><tbody>{reservations.map((r) => { const releasable = Number(r.reserved_qty) - Number(r.consumed_qty) - Number(r.released_qty ?? 0); return <tr key={r.id}><td>{r.items?.item_code} - {r.items?.name}</td><td>{r.warehouses?.code}</td><td>{r.lots?.lot_number ?? ''}</td><td>{r.reserved_qty}</td><td>{r.consumed_qty}</td><td>{r.released_qty ?? 0}</td><td><span className="badge">{r.status}</span></td><td><button className="button small secondary" disabled={releasable <= 0 || !['ACTIVE','PARTIALLY_CONSUMED'].includes(r.status)} onClick={() => releaseReservation(r.id)}>Release</button></td></tr>; })}</tbody></table></div>
              </section>

              <section className="panel">
                <h2>Consumption history</h2>
                <p>Material issue records. Reversal restores stock and reservation quantities when possible.</p>
                <div className="tableWrap"><table><thead><tr><th>Time</th><th>Item</th><th>Warehouse</th><th>Lot</th><th>Qty</th><th>Status</th><th></th></tr></thead><tbody>{consumptions.map((c) => <tr key={c.id}><td>{new Date(c.consumed_at).toLocaleString()}</td><td>{c.items?.item_code}</td><td>{c.warehouses?.code}</td><td>{c.lots?.lot_number ?? ''}</td><td>{c.quantity}</td><td><span className="badge">{c.is_reversed ? 'REVERSED' : 'POSTED'}</span></td><td><button className="button small secondary" disabled={c.is_reversed || order.status === 'FINISHED'} onClick={() => reverseConsumption(c.id)}>Reverse</button></td></tr>)}</tbody></table></div>
              </section>

              <section className="panel">
                <h2>Receipt history</h2>
                <p>Finished goods receipts. Reversal is allowed only if stock is still available.</p>
                <div className="tableWrap"><table><thead><tr><th>Time</th><th>Item</th><th>Warehouse</th><th>Lot</th><th>Good</th><th>Scrap</th><th>Status</th><th></th></tr></thead><tbody>{receipts.map((r) => <tr key={r.id}><td>{new Date(r.received_at).toLocaleString()}</td><td>{r.items?.item_code}</td><td>{r.warehouses?.code}</td><td>{r.lots?.lot_number ?? ''}</td><td>{r.quantity_good}</td><td>{r.quantity_scrap}</td><td><span className="badge">{r.is_reversed ? 'REVERSED' : 'POSTED'}</span></td><td><button className="button small secondary" disabled={r.is_reversed} onClick={() => reverseReceipt(r.id)}>Reverse</button></td></tr>)}</tbody></table></div>
              </section>

              <section className="panel">
                <h2>Operations</h2>
                <p>Routing snapshot created at release. MES-lite controls record start/stop and quantity events.</p>
                <div className="tableWrap"><table><thead><tr><th>Seq</th><th>Operation</th><th>Work center</th><th>Status</th><th>Completed</th><th>Scrap</th><th>Actions</th><th>Report</th></tr></thead><tbody>{operations.map((op) => {
                  const report = operationReport[op.id] ?? { good: 0, scrap: 0, reason: '', note: '' };
                  return <tr key={op.id}><td>{op.sequence_no}</td><td>{op.operation_code} - {op.operation_name}</td><td>{op.work_centers?.code}</td><td><span className="badge">{op.status}</span></td><td>{op.completed_quantity}</td><td>{op.scrap_quantity}</td><td><div className="opButtons"><button className="button small" disabled={op.status === 'IN_PROGRESS' || op.status === 'COMPLETED' || order.status === 'FINISHED'} onClick={() => operationAction(op.id, 'start')}>{op.status === 'PAUSED' ? 'Resume' : 'Start'}</button><button className="button small secondary" disabled={op.status !== 'IN_PROGRESS'} onClick={() => operationAction(op.id, 'pause')}>Pause</button><button className="button small secondary" disabled={!['IN_PROGRESS','PAUSED'].includes(op.status)} onClick={() => operationAction(op.id, 'stop')}>Stop</button></div></td><td><div className="operationReport"><input type="number" min="0" step="0.0001" value={report.good} onChange={(e) => setOperationReport({ ...operationReport, [op.id]: { ...report, good: Number(e.target.value) } })} placeholder="Good" /><input type="number" min="0" step="0.0001" value={report.scrap} onChange={(e) => setOperationReport({ ...operationReport, [op.id]: { ...report, scrap: Number(e.target.value) } })} placeholder="Scrap" /><select value={report.reason} onChange={(e) => setOperationReport({ ...operationReport, [op.id]: { ...report, reason: e.target.value } })}><option value="">Reason</option>{scrapReasons.map((r) => <option key={r.id} value={r.code}>{r.code}</option>)}</select><button className="button small" disabled={op.status === 'COMPLETED' || order.status === 'FINISHED'} onClick={() => reportOperation(op.id, false)}>Report</button><button className="button small" disabled={op.status === 'COMPLETED' || order.status === 'FINISHED'} onClick={() => reportOperation(op.id, true)}>Complete</button></div></td></tr>;
                })}</tbody></table></div>
                {!operations.length && <p className="warning">No routing snapshot. Routing is optional for release but required for MES execution.</p>}
              </section>
            </section>

            <section className="panel withTopMargin">
              <h2>Operation event history</h2>
              <p>Immutable MES-lite event log for this production order.</p>
              <div className="tableWrap"><table><thead><tr><th>Time</th><th>Event</th><th>Operation</th><th>Good</th><th>Scrap</th><th>Reason</th><th>Machine</th><th>Status</th><th></th></tr></thead><tbody>{events.map((event) => <tr key={event.id}><td>{new Date(event.event_time).toLocaleString()}</td><td><span className="badge">{event.event_type}</span></td><td>{event.production_order_operations?.sequence_no} {event.production_order_operations?.operation_code}</td><td>{event.quantity_good}</td><td>{event.quantity_scrap}</td><td>{event.reason_code}</td><td>{event.machines?.code}</td><td><span className="badge">{event.is_reversed ? 'REVERSED' : 'POSTED'}</span></td><td><button className="button small secondary" disabled={event.is_reversed || !['REPORT_QTY','REPORT_SCRAP','COMPLETE'].includes(event.event_type)} onClick={() => reverseOperationEvent(event.id)}>Reverse</button></td></tr>)}</tbody></table></div>
            </section>

            <section className="panel withTopMargin">
              <h2>Finished goods receipt</h2>
              <p>Receive good quantity into finished goods warehouse and optional scrap into scrap warehouse. This updates inventory ledger and production order quantities.</p>
              <div className="receiptGrid">
                <label>FG warehouse<select value={receipt.warehouse_id} onChange={(e) => setReceipt({ ...receipt, warehouse_id: e.target.value })}>{warehouses.map((w) => <option key={w.id} value={w.id}>{w.code} - {w.name}</option>)}</select></label>
                <label>Good qty<input type="number" min="0" step="0.0001" value={receipt.quantity_good} onChange={(e) => setReceipt({ ...receipt, quantity_good: Number(e.target.value) })} /></label>
                <label>Scrap warehouse<select value={receipt.scrap_warehouse_id} onChange={(e) => setReceipt({ ...receipt, scrap_warehouse_id: e.target.value })}><option value="">None</option>{warehouses.map((w) => <option key={w.id} value={w.id}>{w.code} - {w.name}</option>)}</select></label>
                <label>Scrap qty<input type="number" min="0" step="0.0001" value={receipt.quantity_scrap} onChange={(e) => setReceipt({ ...receipt, quantity_scrap: Number(e.target.value) })} /></label>
                <label>Lot number<input value={receipt.lot_number} onChange={(e) => setReceipt({ ...receipt, lot_number: e.target.value })} placeholder="required only if finished item is lot-tracked" /></label>
                <label className="checkboxRow"><input type="checkbox" checked={receipt.finish_order} onChange={(e) => setReceipt({ ...receipt, finish_order: e.target.checked })} /> Finish/close order</label>
              </div>
              <button className="button" disabled={!receipt.warehouse_id || order.status === 'FINISHED'} onClick={receiveGoods}>Receive finished goods</button>
            </section>
          </>
        )}
      </main>
    </>
  );
}
