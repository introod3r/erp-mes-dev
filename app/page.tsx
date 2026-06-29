import Link from 'next/link';
import { ModuleLauncher } from '@/components/ModuleLauncher';

export default function HomePage() {
  return (
    <main className="pageShell wide">
      <header className="hero">
        <div>
          <div className="eyebrow">ERP / MES-lite</div>
          <h1>Metal Fittings ERP/MES</h1>
          <p>Operational starter for inventory, production orders, MES execution, quality and corrections.</p>
          <div className="heroActions">
            <Link className="button" href="/login">Login / Sign up</Link>
            <Link className="button secondary" href="/dashboard">Open dashboard</Link>
            <Link className="button secondary" href="/onboarding">Company onboarding</Link>
          </div>
        </div>
      </header>

      <ModuleLauncher />

      <section className="panel withTopMargin">
        <h2>Recommended first run</h2>
        <div className="flow">
          <div className="flowStep">1. Login</div>
          <div className="flowStep">2. Onboarding</div>
          <div className="flowStep">3. Items / Warehouses</div>
          <div className="flowStep">4. Inventory</div>
          <div className="flowStep">5. Production</div>
        </div>
      </section>
    </main>
  );
}
