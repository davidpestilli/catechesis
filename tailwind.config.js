/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        border: 'hsl(var(--border))',
        input: 'hsl(var(--input))',
        ring: 'hsl(var(--ring))',
        background: 'hsl(var(--background))',
        foreground: 'hsl(var(--foreground))',
        primary: {
          DEFAULT: 'hsl(var(--primary))',
          foreground: 'hsl(var(--primary-foreground))',
        },
        secondary: {
          DEFAULT: 'hsl(var(--secondary))',
          foreground: 'hsl(var(--secondary-foreground))',
        },
        muted: {
          DEFAULT: 'hsl(var(--muted))',
          foreground: 'hsl(var(--muted-foreground))',
        },
        accent: {
          DEFAULT: 'hsl(var(--accent))',
          foreground: 'hsl(var(--accent-foreground))',
        },
        card: {
          DEFAULT: 'hsl(var(--card))',
          foreground: 'hsl(var(--card-foreground))',
        },
      },
      borderRadius: {
        lg: 'var(--radius)',
        md: 'calc(var(--radius) - 2px)',
        sm: 'calc(var(--radius) - 4px)',
      },
      boxShadow: {
        halo: '0 18px 55px rgba(37, 44, 26, 0.16)',
      },
      fontFamily: {
        display: ['"Fraunces"', 'serif'],
        gothic: ['"UnifrakturCook"', 'serif'],
        body: ['"Cormorant Garamond"', 'serif'],
      },
      backgroundImage: {
        'ink-glow':
          'radial-gradient(circle at top, rgba(209, 176, 94, 0.28), transparent 32%), linear-gradient(180deg, rgba(251, 247, 235, 1) 0%, rgba(243, 236, 215, 1) 100%)',
      },
    },
  },
  plugins: [],
}
