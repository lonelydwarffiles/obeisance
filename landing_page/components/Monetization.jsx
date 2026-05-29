import { Check } from 'lucide-react';

const bullets = [
  'Automated Invoicing',
  'Zero Middlemen',
  'Direct Crypto Settlement',
];

export default function Monetization() {
  return (
    <section className="section-shell">
      <div className="grid items-center gap-12 md:grid-cols-[1.1fr_0.9fr]">
        <div>
          <h2 className="heading-display font-serif text-3xl sm:text-4xl">
            Frictionless Tribute.
          </h2>
          <p className="copy-base mt-6 max-w-2xl">
            Your rules, your revenue. Set your own management fees. The platform
            securely generates crypto invoices for your subjects, splitting the
            infrastructure cost and routing your tribute directly to your
            self-hosted wallet. We handle the enforcement; you keep the control.
          </p>

          <ul className="mt-8 space-y-4">
            {bullets.map((item) => (
              <li
                key={item}
                className="flex items-center gap-3 font-sans text-violet-100"
              >
                <span className="flex h-7 w-7 items-center justify-center bg-royal/70 shadow-aura">
                  <Check className="h-4 w-4 text-amethyst" />
                </span>
                <span>{item}</span>
              </li>
            ))}
          </ul>
        </div>

        <div className="relative h-72 w-full overflow-hidden bg-[#12081d] shadow-aura md:h-96">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(155,48,255,0.35),rgba(10,10,10,0)_55%)]" />
          <div className="absolute -left-14 top-10 h-[2px] w-[135%] bg-gradient-to-r from-transparent via-amethyst/60 to-transparent" />
          <div className="absolute -left-20 top-24 h-[2px] w-[140%] bg-gradient-to-r from-transparent via-violet-300/30 to-transparent" />
          <div className="absolute -left-10 top-40 h-[2px] w-[130%] bg-gradient-to-r from-transparent via-amethyst/45 to-transparent" />
          <div className="absolute right-8 top-16 h-36 w-36 bg-[conic-gradient(from_120deg,rgba(155,48,255,0.55),rgba(46,8,84,0.15),rgba(155,48,255,0.45))] blur-sm" />
          <div className="absolute bottom-8 left-8 h-20 w-44 bg-royal/50 blur-xl" />
        </div>
      </div>
    </section>
  );
}
