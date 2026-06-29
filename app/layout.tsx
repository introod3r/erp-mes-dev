import './globals.css';
import type { Metadata } from 'next';
import type { ReactNode } from 'react';
import { LanguageProvider } from '@/components/LanguageProvider';

export const metadata: Metadata = {
  title: 'Metal Fittings ERP/MES',
  description: 'Production management starter for discrete manufacturing',
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <LanguageProvider>{children}</LanguageProvider>
      </body>
    </html>
  );
}
