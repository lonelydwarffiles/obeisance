import { Inter, Playfair_Display } from 'next/font/google';
import './globals.css';

const inter = Inter({
  subsets: ['latin'],
  variable: '--font-inter',
});

const playfair = Playfair_Display({
  subsets: ['latin'],
  variable: '--font-playfair',
});

export const metadata = {
  title: 'Obeisance | Dom-Centric Control',
  description:
    'Hardware-level MDM control for modern Authorities. Architected for absolute device governance.',
};

export default function RootLayout({ children }) {
  return (
    <html lang="en" className={`${inter.variable} ${playfair.variable}`}>
      <body className="bg-obsidian font-sans text-violet-50 antialiased">{children}</body>
    </html>
  );
}
