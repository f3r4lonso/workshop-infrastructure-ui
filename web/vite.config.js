import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Served by server/server.py from web/dist on the same origin as /api.
export default defineConfig({
  base: './',
  plugins: [react()],
  build: { outDir: 'dist', emptyOutDir: true },
  server: {
    proxy: { '/api': 'http://127.0.0.1:8770' },
  },
});
