'use client';

import { FormEvent, useEffect, useMemo, useState } from 'react';
import { AppNav } from './AppNav';
import { CompanySelect, useCompany } from './useCompany';

type Item = { id: string; item_code: string; name: string; item_type: string; default_uom_id: string };
type Bom = { id: string; bom_code: string; version: string; status: string; is_default: boolean; parent_item_id: string; items?: { item_code: string; name: string } };
type BomLine = { id: string; quantity_per: number; scrap_factor_percent: number; issue_method: string; operation_sequence?: number | null; items?: { item_code: string; name: string }; units_of_measure?: { code: string; symbol: string } };
type WorkCenter = { id: string; code: string; name: string };
type Routing = { id: string; routing_code: string; version: string; status: string; is_default: boolean; item_id: string; items?: { item_code: string; name: string } };
type RoutingOperation = { id: string; sequence_no: number; operation_code: string; operation_name: string; setup_time_minutes: number; run_time_minutes_per_unit: number; work_centers?: { code: string; name: string } };

function today() { return new Date().toISOString().slice(0, 10); }

export function BomRoutingManager() {
  const { companies, companyId, setCompanyId } = useCompany();
  const [items, setItems] = useState<Item[]>([]);
  const [boms, setBoms] = useState<Bom[]>([]);
  const [bomLines, setBomLines] = useState<BomLine[]>([]);
  const [selectedBomId, setSelectedBomId] = useState('');
  const [workCenters, setWorkCenters] = useState<WorkCenter[]>([]);
  const [routings, setRoutings] = useState<Routing[]>([]);
  const [routingOperations, setRoutingOperations] = useState<RoutingOperation[]>([]);
  const [selectedRoutingId, setSelectedRoutingId] = useState('');
  const [message, setMessage] = useState<string | null>(null);

  const manufacturedItems = useMemo(() => items.filter((i) => ['SEMI_FINISHED', 'FINISHED_GOOD'].includes(i.item_type)), [items]);
  const componentItems = useMemo(() => items.filter((i) => i.item_type !== 'SERVICE'), [items]);

  const [bomForm, setBomForm] = useState({ parent_item_id: '', bom_code: '', version: '1', status: 'ACTIVE', is_default: true });
  const [lineForm, setLineForm] = useState({ component_item_id: '', quantity_per: 1, scrap_factor_percent: 0, issue_method: 'MANUAL', operation_sequence: '' });
  const [routingForm, setRoutingForm] = useState({ item_id: '', routing_code: '', version: '1', status: 'ACTIVE', is_default: true });
  const [opForm, setOpForm] = useState({ sequence_no: 10, operation_code: '', operation_name: '', work_center_id: '', setup_time_minutes: 0, run_time_minutes_per_unit: 0 });

  async function load() {
    if (!companyId) return;
    const [itemRes, bomRes, wcRes, routingRes] = await Promise.all([
      fetch(`/api/items?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/boms?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/work-centers?company_id=${companyId}`).then((r) => r.json()),
      fetch(`/api/routings?company_id=${companyId}`).then((r) => r.json()),
    ]);
    const itemList = itemRes.data ?? [];
    const bomList = bomRes.data ?? [];
    const wcList = wcRes.data ?? [];
    const routingList = routingRes.data ?? [];
    setItems(itemList);
    setBoms(bomList);
    setWorkCenters(wcList);
    setRoutings(routingList);
    setBomForm((old) => ({ ...old, parent_item_id: old.parent_item_id || itemList.find((i: Item) => ['SEMI_FINISHED','FINISHED_GOOD'].includes(i.item_type))?.id || '' }));
    setLineForm((old) => ({ ...old, component_item_id: old.component_item_id || itemList[0]?.id || '' }));
    setRoutingForm((old) => ({ ...old, item_id: old.item_id || itemList.find((i: Item) => ['SEMI_FINISHED','FINISHED_GOOD'].includes(i.item_type))?.id || '' }));
    setOpForm((old) => ({ ...old, work_center_id: old.work_center_id || wcList[0]?.id || '' }));
    if (!selectedBomId && bomList[0]?.id) setSelectedBomId(bomList[0].id);
    if (!selectedRoutingId && routingList[0]?.id) setSelectedRoutingId(routingList[0].id);
  }

  async function loadBomLines(bomId: string) {
    if (!bomId) { setBomLines([]); return; }
    const res = await fetch(`/api/bom-lines?bom_id=${bomId}`);
    const json = await res.json();
    setBomLines(json.data ?? []);
  }

  async function loadRoutingOperations(routingId: string) {
    if (!routingId) { setRoutingOperations([]); return; }
    const res = await fetch(`/api/routing-operations?routing_id=${routingId}`);
    const json = await res.json();
    setRoutingOperations(json.data ?? []);
  }

  useEffect(() => { load(); }, [companyId]);
  useEffect(() => { loadBomLines(selectedBomId); }, [selectedBomId]);
  useEffect(() => { loadRoutingOperations(selectedRoutingId); }, [selectedRoutingId]);

  async function createBom(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    const parent = items.find((i) => i.id === bomForm.parent_item_id);
    if (!parent) { setMessage('Select parent item'); return; }
    const code = bomForm.bom_code || `${parent.item_code}-BOM`;
    const res = await fetch('/api/boms', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ company_id: companyId, ...bomForm, bom_code: code, valid_from: today(), output_quantity: 1, output_uom_id: parent.default_uom_id }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error?.message ?? JSON.stringify(json.error)); return; }
    setSelectedBomId(json.data.id);
    setBomForm({ ...bomForm, bom_code: '' });
    await load();
  }

  async function addBomLine(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    const component = items.find((i) => i.id === lineForm.component_item_id);
    if (!component || !selectedBomId) { setMessage('Select BOM and component'); return; }
    const payload = {
      company_id: companyId,
      bom_id: selectedBomId,
      component_item_id: lineForm.component_item_id,
      quantity_per: Number(lineForm.quantity_per),
      uom_id: component.default_uom_id,
      scrap_factor_percent: Number(lineForm.scrap_factor_percent),
      issue_method: lineForm.issue_method,
      operation_sequence: lineForm.operation_sequence ? Number(lineForm.operation_sequence) : null,
    };
    const res = await fetch('/api/bom-lines', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error?.message ?? JSON.stringify(json.error)); return; }
    setLineForm({ ...lineForm, quantity_per: 1, scrap_factor_percent: 0, operation_sequence: '' });
    await loadBomLines(selectedBomId);
  }

  async function createRouting(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    const item = items.find((i) => i.id === routingForm.item_id);
    if (!item) { setMessage('Select item'); return; }
    const code = routingForm.routing_code || `${item.item_code}-RTG`;
    const res = await fetch('/api/routings', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ company_id: companyId, ...routingForm, routing_code: code, valid_from: today() }),
    });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error?.message ?? JSON.stringify(json.error)); return; }
    setSelectedRoutingId(json.data.id);
    setRoutingForm({ ...routingForm, routing_code: '' });
    await load();
  }

  async function addRoutingOperation(event: FormEvent) {
    event.preventDefault();
    setMessage(null);
    if (!selectedRoutingId) { setMessage('Select routing'); return; }
    const payload = {
      company_id: companyId,
      routing_id: selectedRoutingId,
      sequence_no: Number(opForm.sequence_no),
      operation_code: opForm.operation_code,
      operation_name: opForm.operation_name,
      work_center_id: opForm.work_center_id,
      setup_time_minutes: Number(opForm.setup_time_minutes),
      run_time_minutes_per_unit: Number(opForm.run_time_minutes_per_unit),
      labor_required: true,
      machine_required: true,
    };
    const res = await fetch('/api/routing-operations', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    const json = await res.json();
    if (!res.ok) { setMessage(json.error?.message ?? JSON.stringify(json.error)); return; }
    setOpForm({ ...opForm, sequence_no: opForm.sequence_no + 10, operation_code: '', operation_name: '', setup_time_minutes: 0, run_time_minutes_per_unit: 0 });
    await loadRoutingOperations(selectedRoutingId);
  }

  return (
    <>
      <AppNav />
      <main className="pageShell wide">
        <div className="pageHeader">
          <div>
            <div className="eyebrow">Engineering master data</div>
            <h1>BOM & Routing</h1>
            <p>Create default active BOMs and routings so production orders can be released.</p>
          </div>
          <CompanySelect companies={companies} companyId={companyId} onChange={setCompanyId} />
        </div>

        {message && <div className="formMessage">{message}</div>}

        <section className="splitPanels">
          <div className="stack">
            <form className="formCard" onSubmit={createBom}>
              <h2>Create BOM</h2>
              <label>Parent item<select value={bomForm.parent_item_id} onChange={(e) => setBomForm({ ...bomForm, parent_item_id: e.target.value })} required>{manufacturedItems.map((item) => <option key={item.id} value={item.id}>{item.item_code} - {item.name}</option>)}</select></label>
              <label>BOM code<input value={bomForm.bom_code} onChange={(e) => setBomForm({ ...bomForm, bom_code: e.target.value })} placeholder="auto: ITEM-BOM" /></label>
              <label>Version<input value={bomForm.version} onChange={(e) => setBomForm({ ...bomForm, version: e.target.value })} required /></label>
              <label>Status<select value={bomForm.status} onChange={(e) => setBomForm({ ...bomForm, status: e.target.value })}><option>ACTIVE</option><option>DRAFT</option><option>OBSOLETE</option></select></label>
              <label className="checkboxRow"><input type="checkbox" checked={bomForm.is_default} onChange={(e) => setBomForm({ ...bomForm, is_default: e.target.checked })} /> Default BOM</label>
              <button className="button" disabled={!companyId || !manufacturedItems.length}>Create BOM</button>
            </form>

            <form className="formCard" onSubmit={addBomLine}>
              <h2>Add BOM line</h2>
              <label>BOM<select value={selectedBomId} onChange={(e) => setSelectedBomId(e.target.value)} required>{boms.map((bom) => <option key={bom.id} value={bom.id}>{bom.bom_code} v{bom.version} - {bom.items?.item_code}</option>)}</select></label>
              <label>Component<select value={lineForm.component_item_id} onChange={(e) => setLineForm({ ...lineForm, component_item_id: e.target.value })} required>{componentItems.map((item) => <option key={item.id} value={item.id}>{item.item_code} - {item.name}</option>)}</select></label>
              <label>Quantity per<input type="number" min="0.000001" step="0.000001" value={lineForm.quantity_per} onChange={(e) => setLineForm({ ...lineForm, quantity_per: Number(e.target.value) })} required /></label>
              <label>Scrap factor %<input type="number" min="0" step="0.0001" value={lineForm.scrap_factor_percent} onChange={(e) => setLineForm({ ...lineForm, scrap_factor_percent: Number(e.target.value) })} /></label>
              <label>Issue method<select value={lineForm.issue_method} onChange={(e) => setLineForm({ ...lineForm, issue_method: e.target.value })}><option>MANUAL</option><option>BACKFLUSH</option></select></label>
              <label>Operation sequence<input value={lineForm.operation_sequence} onChange={(e) => setLineForm({ ...lineForm, operation_sequence: e.target.value })} placeholder="optional" /></label>
              <button className="button" disabled={!selectedBomId || !componentItems.length}>Add component</button>
            </form>
          </div>

          <div className="stack">
            <section className="panel">
              <h2>BOM lines</h2>
              <div className="tableWrap"><table><thead><tr><th>Component</th><th>Qty</th><th>UOM</th><th>Scrap %</th><th>Issue</th></tr></thead><tbody>{bomLines.map((l) => <tr key={l.id}><td>{l.items?.item_code} - {l.items?.name}</td><td>{l.quantity_per}</td><td>{l.units_of_measure?.code}</td><td>{l.scrap_factor_percent}</td><td>{l.issue_method}</td></tr>)}</tbody></table></div>
            </section>
          </div>
        </section>

        <section className="splitPanels withTopMargin">
          <div className="stack">
            <form className="formCard" onSubmit={createRouting}>
              <h2>Create routing</h2>
              <label>Item<select value={routingForm.item_id} onChange={(e) => setRoutingForm({ ...routingForm, item_id: e.target.value })} required>{manufacturedItems.map((item) => <option key={item.id} value={item.id}>{item.item_code} - {item.name}</option>)}</select></label>
              <label>Routing code<input value={routingForm.routing_code} onChange={(e) => setRoutingForm({ ...routingForm, routing_code: e.target.value })} placeholder="auto: ITEM-RTG" /></label>
              <label>Version<input value={routingForm.version} onChange={(e) => setRoutingForm({ ...routingForm, version: e.target.value })} required /></label>
              <label>Status<select value={routingForm.status} onChange={(e) => setRoutingForm({ ...routingForm, status: e.target.value })}><option>ACTIVE</option><option>DRAFT</option><option>OBSOLETE</option></select></label>
              <label className="checkboxRow"><input type="checkbox" checked={routingForm.is_default} onChange={(e) => setRoutingForm({ ...routingForm, is_default: e.target.checked })} /> Default routing</label>
              <button className="button" disabled={!companyId || !manufacturedItems.length}>Create routing</button>
            </form>

            <form className="formCard" onSubmit={addRoutingOperation}>
              <h2>Add operation</h2>
              <label>Routing<select value={selectedRoutingId} onChange={(e) => setSelectedRoutingId(e.target.value)} required>{routings.map((r) => <option key={r.id} value={r.id}>{r.routing_code} v{r.version} - {r.items?.item_code}</option>)}</select></label>
              <label>Sequence<input type="number" value={opForm.sequence_no} onChange={(e) => setOpForm({ ...opForm, sequence_no: Number(e.target.value) })} required /></label>
              <label>Operation code<input value={opForm.operation_code} onChange={(e) => setOpForm({ ...opForm, operation_code: e.target.value })} required placeholder="STAMP" /></label>
              <label>Operation name<input value={opForm.operation_name} onChange={(e) => setOpForm({ ...opForm, operation_name: e.target.value })} required placeholder="Stamping" /></label>
              <label>Work center<select value={opForm.work_center_id} onChange={(e) => setOpForm({ ...opForm, work_center_id: e.target.value })} required>{workCenters.map((wc) => <option key={wc.id} value={wc.id}>{wc.code} - {wc.name}</option>)}</select></label>
              <label>Setup minutes<input type="number" min="0" step="0.01" value={opForm.setup_time_minutes} onChange={(e) => setOpForm({ ...opForm, setup_time_minutes: Number(e.target.value) })} /></label>
              <label>Run minutes/unit<input type="number" min="0" step="0.000001" value={opForm.run_time_minutes_per_unit} onChange={(e) => setOpForm({ ...opForm, run_time_minutes_per_unit: Number(e.target.value) })} /></label>
              <button className="button" disabled={!selectedRoutingId || !workCenters.length}>Add operation</button>
            </form>
          </div>

          <div className="stack">
            <section className="panel">
              <h2>Routing operations</h2>
              <div className="tableWrap"><table><thead><tr><th>Seq</th><th>Code</th><th>Name</th><th>Work center</th><th>Setup</th><th>Run/unit</th></tr></thead><tbody>{routingOperations.map((op) => <tr key={op.id}><td>{op.sequence_no}</td><td>{op.operation_code}</td><td>{op.operation_name}</td><td>{op.work_centers?.code}</td><td>{op.setup_time_minutes}</td><td>{op.run_time_minutes_per_unit}</td></tr>)}</tbody></table></div>
            </section>
          </div>
        </section>
      </main>
    </>
  );
}
