import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { copyFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { version } from './package.json';

const output = fileURLToPath(new URL('../res/web/finEnergy/', import.meta.url));
const edition = process.env.FINENERGY_BUILD_EDITION ?? 'hq';
if (edition !== 'china' && edition !== 'hq') throw new Error('Unknown FIN Energy edition.');
const buildInfo = {
  version, edition,
  licenseMode: edition === 'china' ? 'selfManaged' : 'finNative',
  sourceCommit: process.env.FINENERGY_BUILD_COMMIT ?? '',
};
export default defineConfig({
  base: './',
  define: { __FIN_ENERGY_CHINA__: JSON.stringify(edition === 'china') },
  plugins: [react(), {
    name: 'versioned-entry',
    apply: 'build',
    closeBundle() {
      copyFileSync(output + 'index.html', output + 'index-' + version + '.html');
      writeFileSync(output + 'build-info.json', JSON.stringify(buildInfo, null, 2) + '\n');
    },
  }],
  build: { manifest: true, outDir: output, emptyOutDir: true, assetsDir: 'modules', chunkSizeWarningLimit: 1800 },
});
