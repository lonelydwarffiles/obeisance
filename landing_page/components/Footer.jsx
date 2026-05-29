export default function Footer() {
  const links = ['Terms of Service', 'Privacy Policy', 'Compliance'];

  return (
    <footer className="px-6 pb-10 pt-14 md:px-10">
      <div className="mx-auto flex w-full max-w-6xl flex-col items-start justify-between gap-5 text-violet-100/70 md:flex-row md:items-center">
        <p className="font-serif text-sm tracking-wide text-violet-200">
          Obeisance | Architected for Authority
        </p>

        <nav className="flex flex-wrap gap-5 text-xs uppercase tracking-[0.12em]">
          {links.map((link) => (
            <a
              key={link}
              href="#"
              className="font-sans transition-colors duration-200 hover:text-amethyst"
            >
              {link}
            </a>
          ))}
        </nav>
      </div>
    </footer>
  );
}
