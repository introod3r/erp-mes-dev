'use client';

import { useEffect, useState } from 'react';
import { AppNav } from './AppNav';
import { CompanySelect, useCompany } from './useCompany';

type Metrics = {
  items: number;
  warehouses: number;
  productionOrders: number;
  openOrders: number;
};

export function OperationalDashboard() {
  const { companies, companyId, setCompanyId, loading, error } = useCompany();
  const [metrics, setMetrics] = useState<Metrics>({ items: 0, warehouses: 0, productionOrders: 0, openOrders: 0 });

  useEffect(() => {
    if (!companyId) return;
    async function load() {
      const [items, warehouses, orders] = await Promise.all([
        fetch(`/api/items?company_id=${companyId}`).then((r) => r.json()),
        fetch(`/api/warehouses?company_id=${companyId}`).then((r) => r.json()),
        fetch(`/api/production-orders?company_id=${companyId}`).then((r) => r.json()),
      ]);
      const orderList = orders.data ?? [];
      setMetrics({
        items: items.data?.length ?? 0,
        warehouses: warehouses.data?.length ?? 0,
        productionOrders: orderList.length,
        openOrders: orderList.filter((o: any) => !['FINISHED', 'CANCELLED'].includes(o.status)).length,
      });
    }
    load();
  }, [companyId]);

  return (
    <>
      <AppNav />
      <main className="pageShell">
        <div className="pageHeader">
          <div>
            <div className="eyebrow">Priority 1</div>
            <h1>Operational dashboard</h1>
            <p>Company context, authentication, and first master-data workflows.</p>
          </div>
          <CompanySelect companies={companies} companyId={companyId} onChange={setCompanyId} />
        </div>

        {loading && <div className="panel">Loading company context...</div>}
        {error && <div className="formMessage">{error}</div>}
        {!loading && !companies.length && <div className="panel warning">No company found. Use onboarding first.</div>}

        <section className="grid">
          <section className="card"><div className="cardTitle">Items</div><div className="cardValue">{metrics.items}</div><div className="cardDetail">Raw, semi-finished, finished, services</div></section>
          <section className="card"><div className="cardTitle">Warehouses</div><div className="cardValue">{metrics.warehouses}</div><div className="cardDetail">RM, WIP, FG, SCRAP, QC</div></section>
          <section className="card"><div className="cardTitle">Production orders</div><div className="cardValue">{metrics.productionOrders}</div><div className="cardDetail">Latest 100 loaded</div></section>
          <section className="card"><div className="cardTitle">Open orders</div><div className="cardValue">{metrics.openOrders}</div><div className="cardDetail">Not finished/cancelled</div></section>
        </section>

        <section className="panel">
          <h2>Next production flow to finish</h2>
          <div className="flow">
            <div className="flowStep">Items</div>
            <div className="flowStep">BOM</div>
            <div className="flowStep">Release PO</div>
            <div className="flowStep">Reserve</div>
            <div className="flowStep">Consume/Receive</div>
          </div>
        </section>
      </main>
    </>
  );
}
