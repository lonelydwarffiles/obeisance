import Hero from '../components/Hero';
import Features from '../components/Features';
import Monetization from '../components/Monetization';
import FAQ from '../components/FAQ';
import Footer from '../components/Footer';

export default function Page() {
  return (
    <main className="relative overflow-x-clip bg-obsidian">
      <Hero />
      <Features />
      <Monetization />
      <FAQ />
      <Footer />
    </main>
  );
}
