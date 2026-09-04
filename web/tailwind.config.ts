import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        control: {
          bg: "#0b1220",
          panel: "#111a2e",
          border: "#1e2a44",
          accent: "#3b82f6",
        },
      },
    },
  },
  plugins: [],
};

export default config;
