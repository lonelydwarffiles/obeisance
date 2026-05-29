/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './app/**/*.{js,jsx,ts,tsx}',
    './components/**/*.{js,jsx,ts,tsx}',
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['var(--font-inter)', 'system-ui', 'sans-serif'],
        serif: ['var(--font-playfair)', 'Georgia', 'serif'],
      },
      colors: {
        obsidian: '#0A0A0A',
        amethyst: '#9B30FF',
        royal: '#2E0854',
      },
      boxShadow: {
        aura: '0 0 0 0 rgba(155, 48, 255, 0), 0 16px 36px -14px rgba(46, 8, 84, 0.85)',
        'aura-hover': '0 0 0 0 rgba(155, 48, 255, 0), 0 22px 54px -20px rgba(155, 48, 255, 0.75)',
      },
      keyframes: {
        pulseCore: {
          '0%, 100%': { opacity: '0.45', transform: 'scale(1)' },
          '50%': { opacity: '0.75', transform: 'scale(1.06)' },
        },
      },
      animation: {
        'pulse-core': 'pulseCore 5s ease-in-out infinite',
      },
    },
  },
  plugins: [],
};
