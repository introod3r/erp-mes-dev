'use client';

import { useLanguage } from './LanguageProvider';
import { LanguageSelector } from './LanguageSelector';

function Card({ title, value, detail }: { title: string; value: string; detail: string }) {
  return (
    <section className="card">
      <div className="cardTitle">{title}</div>
      <div className="cardValue">{value}</div>
      <div className="cardDetail">{detail}</div>
    </section>
  );
}

export function Dashboard() {
  const { t } = useLanguage();

  return (
    <main className="pageShell">
      <header className="hero">
        <div>
          <div className="eyebrow">ERP / MES-lite</div>
          <h1>{t('appTitle')}</h1>
          <p>{t('subtitle')}</p>
        </div>
        <LanguageSelector />
      </header>

      <section className="grid">
        <Card title={t('productionOrders')} value="10k+/month" detail={`${t('planned')} • ${t('released')} • ${t('inProgress')} • ${t('finished')}`} />
        <Card title={t('inventory')} value="Ledger-based" detail={`${t('stockOnHand')} - ${t('reserved')} = ${t('available')}`} />
        <Card title={t('bomRouting')} value="Versioned" detail="BOM snapshots, routing operations, work centers" />
        <Card title={t('mesExecution')} value="Events" detail={`${t('start')} / ${t('stop')} / ${t('goodQty')} / ${t('scrapQty')}`} />
      </section>

      <section className="panel">
        <h2>{t('dashboard')}</h2>
        <p>{t('starterNote')}</p>
        <p className="warning">{t('criticalNote')}</p>
      </section>

      <section className="moduleGrid">
        {[t('items'), t('warehouses'), t('productionOrders'), t('quality')].map((label) => (
          <div className="module" key={label}>{label}</div>
        ))}
      </section>
    </main>
  );
}
