'use client';

import { motion } from 'framer-motion';
import { ClipboardList, Eye, Lock } from 'lucide-react';

const features = [
  {
    title: 'Unyielding Restriction',
    copy:
      'Set daily app limits, enforce blackout hours, or lock the device into a single application remotely. No bypasses. No negotiating.',
    Icon: Lock,
  },
  {
    title: 'Tamper-Proof Visibility',
    copy:
      'Trust is earned through verification. Access immutable usage logs to see exactly where their time is spent.',
    Icon: Eye,
  },
  {
    title: 'The Structured Dynamic',
    copy:
      'Assign daily tasks, demand reflection through the Confessional, and maintain a direct, structured line of communication.',
    Icon: ClipboardList,
  },
];

export default function Features() {
  return (
    <section className="section-shell">
      <div className="mx-auto mb-12 max-w-2xl text-center">
        <h2 className="heading-display font-serif text-3xl sm:text-4xl">
          The Arsenal
        </h2>
      </div>

      <div className="grid gap-6 md:grid-cols-3">
        {features.map((feature, idx) => (
          <motion.article
            key={feature.title}
            initial={{ opacity: 0, y: 28 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, amount: 0.35 }}
            transition={{ duration: 0.6, delay: idx * 0.12 }}
            className="group bg-[#12081d] p-7 shadow-aura transition-all duration-300 hover:-translate-y-1 hover:shadow-aura-hover"
          >
            <feature.Icon className="h-7 w-7 text-amethyst" strokeWidth={1.6} />
            <h3 className="mt-5 font-serif text-2xl text-white">{feature.title}</h3>
            <p className="mt-4 font-sans leading-relaxed text-violet-100/75">
              {feature.copy}
            </p>
          </motion.article>
        ))}
      </div>
    </section>
  );
}
