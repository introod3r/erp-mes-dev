import Link from 'next/link';

const modules = [
  { href: '/login', title: 'Login', desc: 'Sign in or create a user account' },
  { href: '/onboarding', title: 'Onboarding', desc: 'Create company and seed basic data' },
  { href: '/items', title: 'Items', desc: 'Create raw materials and finished goods' },
  { href: '/warehouses', title: 'Warehouses', desc: 'Create storage areas' },
  { href: '/inventory', title: 'Inventory', desc: 'Post stock receipts and review balances' },
  { href: '/resources', title: 'Resources', desc: 'Work centers and machines' },
  { href: '/bom-routing', title: 'BOM/Routing', desc: 'Create BOMs and operations' },
  { href: '/production-orders', title: 'Production Orders', desc: 'Create, release and execute orders' },
  { href: '/operator', title: 'Operator Queue', desc: 'Shop-floor execution queue' },
  { href: '/quality', title: 'Quality', desc: 'NCR and quarantine stock' },
  { href: '/inspections', title: 'Inspections', desc: 'Inspection plans and results' },
  { href: '/corrections', title: 'Corrections', desc: 'Approval workflow for reversals' },
];

export function ModuleLauncher() {
  return (
    <section className="panel withTopMargin">
      <div className="sectionHeader">
        <div>
          <h2>Application modules</h2>
          <p>Use these entry points to manipulate the ERP/MES system.</p>
        </div>
      </div>
      <div className="launcherGrid">
        {modules.map((m) => (
          <Link key={m.href} href={m.href} className="launcherCard">
            <strong>{m.title}</strong>
            <span>{m.desc}</span>
          </Link>
        ))}
      </div>
    </section>
  );
}
