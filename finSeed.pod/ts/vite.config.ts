import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
export default defineConfig({ base: './', plugins: [react()], build: {outDir: '../res/web/seed', emptyOutDir: true, assetsDir: 'modules', chunkSizeWarningLimit: 1800} });
