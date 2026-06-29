'use client';

import en from '@/locales/en.json';
import sr from '@/locales/sr.json';
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';

type Lang = 'en' | 'sr';
type Dict = typeof en;

const dictionaries: Record<Lang, Dict> = { en, sr };

const LanguageContext = createContext<{
  lang: Lang;
  setLang: (lang: Lang) => void;
  t: (key: keyof Dict) => string;
} | null>(null);

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Lang>('en');

  useEffect(() => {
    const saved = window.localStorage.getItem('lang');
    if (saved === 'en' || saved === 'sr') setLangState(saved);
  }, []);

  const setLang = (next: Lang) => {
    setLangState(next);
    window.localStorage.setItem('lang', next);
  };

  const value = useMemo(
    () => ({
      lang,
      setLang,
      t: (key: keyof Dict) => dictionaries[lang][key] ?? key,
    }),
    [lang]
  );

  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
}

export function useLanguage() {
  const ctx = useContext(LanguageContext);
  if (!ctx) throw new Error('useLanguage must be used inside LanguageProvider');
  return ctx;
}
