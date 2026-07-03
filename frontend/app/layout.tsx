import type { Metadata } from 'next';
import { Providers } from './providers';
import './globals.css';

export const metadata: Metadata = {
  title: 'Ritual Quest Passport',
  description:
    'Complete 3 on-chain quests on Ritual Chain testnet — on-chain AI inference, HTTP data fetching, and scheduled execution — and earn soulbound badges.',
  openGraph: {
    title: 'Ritual Quest Passport',
    description: 'Earn soulbound badges by using Ritual Chain\'s on-chain AI, HTTP, and Scheduler on testnet.',
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
