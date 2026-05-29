export default function Hero() {
  return (
    <section className="relative flex min-h-screen items-center justify-center px-6 py-24 text-center md:px-10">
      <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
        <div className="h-[38rem] w-[38rem] animate-pulse-core rounded-full bg-[radial-gradient(circle,rgba(46,8,84,0.55)_0%,rgba(46,8,84,0.2)_35%,rgba(10,10,10,0)_72%)]" />
      </div>

      <div className="relative z-10 mx-auto max-w-4xl">
        <h1 className="heading-display font-serif text-5xl sm:text-6xl md:text-7xl">
          Their Screen. Your Rules.
        </h1>

        <p className="copy-base mx-auto mt-8 max-w-3xl text-lg text-violet-100/85 md:text-xl">
          Willpower is flawed. Hardware enforcement is absolute. Take complete,
          remote control over their device with a management suite built
          exclusively for the modern Authority.
        </p>

        <div className="mt-10">
          <button className="inline-flex items-center justify-center bg-amethyst px-8 py-3 font-sans text-sm font-semibold uppercase tracking-[0.14em] text-white shadow-aura transition-all duration-300 hover:shadow-aura-hover focus:outline-none focus-visible:ring-2 focus-visible:ring-amethyst/70">
            Establish Control
          </button>
          <p className="mt-5 font-sans text-sm tracking-wide text-violet-200/65">
            Invitation Only. Claim your first subject at no cost.
          </p>
        </div>
      </div>
    </section>
  );
}
