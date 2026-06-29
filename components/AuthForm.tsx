'use client';

import { FormEvent, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createSupabaseBrowserClient } from '@/lib/supabase/browser';

export function AuthForm() {
  const supabase = createSupabaseBrowserClient();
  const router = useRouter();
  const [mode, setMode] = useState<'signIn' | 'signUp'>('signIn');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault();
    setLoading(true);
    setMessage(null);

    const result = mode === 'signIn'
      ? await supabase.auth.signInWithPassword({ email, password })
      : await supabase.auth.signUp({ email, password });

    setLoading(false);
    if (result.error) {
      setMessage(result.error.message);
      return;
    }

    if (mode === 'signUp' && !result.data.session) {
      setMessage('Account created. Please confirm your email, then sign in.');
      return;
    }

    router.push('/dashboard');
  }

  return (
    <form className="formCard" onSubmit={submit}>
      <h1>{mode === 'signIn' ? 'Sign in' : 'Create account'}</h1>
      <p>Use Supabase Auth. After first login, create your company in onboarding.</p>

      <label>
        Email
        <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
      </label>
      <label>
        Password
        <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} minLength={6} required />
      </label>

      {message && <div className="formMessage">{message}</div>}

      <button className="button" disabled={loading}>{loading ? 'Please wait...' : mode === 'signIn' ? 'Sign in' : 'Create account'}</button>
      <button
        type="button"
        className="linkButton"
        onClick={() => setMode(mode === 'signIn' ? 'signUp' : 'signIn')}
      >
        {mode === 'signIn' ? 'Need an account? Create one' : 'Already have an account? Sign in'}
      </button>
    </form>
  );
}
