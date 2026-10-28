import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import {copyFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {version} from './package.json';
const output=fileURLToPath(new URL('../res/web/enerCubix/',import.meta.url));
export default defineConfig({ base: './', plugins: [react(),{name:'versioned-entry',closeBundle(){copyFileSync(output+'index.html',output+`index-${version}.html`);}}], build: {outDir: '../res/web/enerCubix', emptyOutDir: true, assetsDir: 'modules', chunkSizeWarningLimit: 1800} });
