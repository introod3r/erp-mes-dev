'use client';

import { FormEvent, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createSupabaseBrowserClient } from '@/lib/supabase/browser';
import { AppNav } from './AppNav';

export function OnboardingForm() {
  const supabase = createSupabaseBrowserClient();
  const router = useRouter();
  const [companyName, setCompanyName] = useState('');
  const [seed, setSeed] = useState(true);
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    setMessage(null);

    const { data: companyId, error } = await supabase.rpc('create_company_with_admin', {
      p_company_name: companyName,
    });

    if (error) {
      setMessage(error.message);
      setLoading(false);
      return;
    }

    if (seed && companyId) {
      const { error: seedError } = await supabase.rpc('seed_basic_master_data', { p_company_id: companyId });
      if (seedError) {
        setMessage(`Company created, but seed failed: ${seedError.message}`);
        setLoading(false);
        return;
      }
    }

    if (companyId) window.localStorage.setItem('company_id', companyId);
    router.push('/dashboard');
  }

  return (
    <>
      <AppNav />
      <main className="pageShell compact">
        <form className="formCard" onSubmit={submit}>
          <h1>Company onboarding</h1>
          <p>Create the company tenant and make the current authenticated user ADMIN.</p>
          <label>
            Company name
            <input value={companyName} onChange={(e) => setCompanyName(e.target.value)} required />
          </label>
          <label className="checkboxRow">
            <input type="checkbox" checked={seed} onChange={(e) => setSeed(e.target.checked)} />
            Seed basic UOMs, warehouses, and sample items
          </label>
          {message && <div className="formMessage">{message}</div>}
          <button className="button" disabled={loading}>{loading ? 'Creating...' : 'Create company'}</button>
        </form>
      </main>
    </>
  );
}
