'use client';

import { useEffect, useState } from 'react';
import { createSupabaseBrowserClient } from '@/lib/supabase/browser';

type Company = { id: string; name: string; role: string };

export function useCompany() {
  const supabase = createSupabaseBrowserClient();
  const [companies, setCompanies] = useState<Company[]>([]);
  const [companyId, setCompanyId] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function load() {
      setLoading(true);
      setError(null);
      const { data, error } = await supabase
        .from('company_memberships')
        .select('role, companies(id,name)')
        .eq('is_active', true);

      if (error) {
        setError(error.message);
        setLoading(false);
        return;
      }

      const list = (data ?? []).map((row: any) => ({
        id: row.companies?.id,
        name: row.companies?.name,
        role: row.role,
      })).filter((x) => x.id && x.name);

      setCompanies(list);
      const saved = window.localStorage.getItem('company_id');
      const selected = list.find((c) => c.id === saved)?.id ?? list[0]?.id ?? '';
      setCompanyId(selected);
      if (selected) window.localStorage.setItem('company_id', selected);
      setLoading(false);
    }
    load();
  }, []);

  function changeCompany(id: string) {
    setCompanyId(id);
    window.localStorage.setItem('company_id', id);
  }

  return { companies, companyId, setCompanyId: changeCompany, loading, error };
}

export function CompanySelect({ companyId, companies, onChange }: { companyId: string; companies: Company[]; onChange: (id: string) => void }) {
  if (!companies.length) return <a className="button" href="/onboarding">Create company</a>;
  return (
    <label className="companySelect">
      Company
      <select value={companyId} onChange={(e) => onChange(e.target.value)}>
        {companies.map((company) => <option key={company.id} value={company.id}>{company.name} ({company.role})</option>)}
      </select>
    </label>
  );
}
