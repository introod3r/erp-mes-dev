'use client';

import { useLanguage } from './LanguageProvider';

export function LanguageSelector() {
  const { lang, setLang, t } = useLanguage();
  return (
    <label className="languageSelector">
      <span>{t('language')}</span>
      <select value={lang} onChange={(e) => setLang(e.target.value as 'en' | 'sr')}>
        <option value="en">{t('english')}</option>
        <option value="sr">{t('serbian')}</option>
      </select>
    </label>
  );
}
