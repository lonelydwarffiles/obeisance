'use client';

import { AnimatePresence, motion } from 'framer-motion';
import { ChevronDown } from 'lucide-react';
import { useState } from 'react';

const items = [
  {
    q: 'Can the subject bypass or delete the profile?',
    a: "No. Obeisance utilizes Device Owner provisioning and Accessibility locks. Once installed, it cannot be removed without the Authority's cryptographic release.",
  },
  {
    q: 'Do I need technical knowledge to deploy this?',
    a: 'No. Generate a secure invite link. Once they tap it, the platform handles the configuration.',
  },
  {
    q: 'How is billing handled?',
    a: 'Subjects are billed via crypto. You set the markup above our base infrastructure fee, and keep 100% of the difference.',
  },
];

export default function FAQ() {
  const [openIndex, setOpenIndex] = useState(0);

  return (
    <section className="section-shell">
      <div className="mx-auto max-w-3xl">
        <h2 className="heading-display mb-10 text-center font-serif text-3xl sm:text-4xl">
          Authority FAQ
        </h2>

        <div className="space-y-3">
          {items.map((item, idx) => {
            const open = idx === openIndex;
            return (
              <div key={item.q} className="bg-[#12081d] shadow-aura">
                <button
                  className="flex w-full items-center justify-between px-6 py-5 text-left"
                  onClick={() => setOpenIndex(open ? -1 : idx)}
                  type="button"
                >
                  <span className="font-serif text-lg text-white">{item.q}</span>
                  <ChevronDown
                    className={`h-5 w-5 text-amethyst transition-transform duration-300 ${
                      open ? 'rotate-180' : ''
                    }`}
                  />
                </button>

                <AnimatePresence initial={false}>
                  {open && (
                    <motion.div
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: 'auto', opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      transition={{ duration: 0.28, ease: 'easeOut' }}
                      className="overflow-hidden"
                    >
                      <p className="px-6 pb-6 font-sans leading-relaxed text-violet-100/80">
                        {item.a}
                      </p>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
