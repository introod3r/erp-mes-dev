'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { createSupabaseBrowserClient } from '@/lib/supabase/browser';
import { LanguageSelector } from './LanguageSelector';

const links = [
  { href: '/dashboard', label: 'Dashboard' },
  { href: '/items', label: 'Items' },
  { href: '/warehouses', label: 'Warehouses' },
  { href: '/inventory', label: 'Inventory' },
  { href: '/resources', label: 'Resources' },
  { href: '/bom-routing', label: 'BOM/Routing' },
  { href: '/reason-codes', label: 'Reasons' },
  { href: '/quality', label: 'Quality' },
  { href: '/inspections', label: 'Inspections' },
  { href: '/corrections', label: 'Corrections' },
  { href: '/operator', label: 'Operator' },
  { href: '/production-orders', label: 'Production Orders' },
];

export function AppNav() {
  const pathname = usePathname();
  const router = useRouter();
  const supabase = createSupabaseBrowserClient();

  async function signOut() {
    await supabase.auth.signOut();
    router.push('/login');
  }

  return (
    <nav className="appNav">
      <Link className="brand" href="/dashboard">ERP/MES</Link>
      <div className="navLinks">
        {links.map((link) => (
          <Link key={link.href} className={pathname === link.href ? 'active' : ''} href={link.href}>
            {link.label}
          </Link>
        ))}
      </div>
      <div className="navActions">
        <LanguageSelector />
        <button className="button secondary" onClick={signOut}>Sign out</button>
      </div>
    </nav>
  );
}
