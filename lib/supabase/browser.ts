import { createBrowserClient } from '@supabase/ssr';

export function createSupabaseBrowserClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL || 'http://localhost:54321';
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || 'dev-placeholder-anon-key';
  return createBrowserClient(url, anonKey);
}
