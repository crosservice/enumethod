import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        bg: '#0d1117',
        card: '#161b22',
        border: '#30363d',
        text: '#e6edf3',
        'text-secondary': '#8b949e',
        accent: '#58a6ff',
        'accent-hover': '#79c0ff',
        success: '#3fb950',
        warning: '#d29922',
        danger: '#f85149',
      },
    },
  },
  plugins: [],
};

export default config;
