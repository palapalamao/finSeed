import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, symlinkSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createPublicKey } from 'node:crypto';

const [sourceArg, stageArg, edition, version, keyring] = process.argv.slice(2);
if (!['china', 'hq'].includes(edition) || !/^\d+\.\d+\.\d+$/.test(version ?? '')) {
  throw new Error('Expected an explicit edition and a three-component release version.');
}
const source = resolve(sourceArg);
const stage = resolve(stageArg);
const pod = 'finEnergy.pod';
if (existsSync(stage)) throw new Error('Build stage already exists.');

function copy(path, options = {}) {
  cpSync(join(source, path), join(stage, path), { recursive: true, ...options });
}

mkdirSync(stage, { recursive: true });
copy('package.json');
copy('scripts/sdk.ps1');
copy('scripts/acceptance.ps1');
copy('scripts/check-versions.mjs');
for (const path of ['fan', 'lib', 'locale', 'test', 'build.fan', join('editions', edition)]) {
  copy(join(pod, path));
}
// The staged build must never inherit a previous UI bundle or a license resource.
for (const path of ['ts', 'res']) {
  const excluded = new Set(path === 'ts'
    ? ['node_modules', 'test-results', 'playwright-report', '.vite']
    : ['web', 'license-keys.json']);
  const sourceDir = join(source, pod, path);
  for (const entry of readdirSync(sourceDir)) {
    if (!excluded.has(entry)) copy(join(pod, path, entry));
  }
}
const modules = join(source, pod, 'ts', 'node_modules');
if (!existsSync(modules)) throw new Error('Run npm ci in finEnergy.pod/ts before building.');
symlinkSync(modules, join(stage, pod, 'ts', 'node_modules'), 'junction');
mkdirSync(join(stage, pod, 'res', 'web'), { recursive: true });

function updateVersion(path, update) {
  const target = join(stage, path);
  const manifest = JSON.parse(readFileSync(target, 'utf8'));
  manifest.version = version;
  update?.(manifest);
  writeFileSync(target, JSON.stringify(manifest, null, 2) + '\n');
}
updateVersion('package.json');
updateVersion(join(pod, 'ts', 'package.json'));
updateVersion(join(pod, 'ts', 'package-lock.json'), manifest => { manifest.packages[''].version = version; });
const build = join(stage, pod, 'build.fan');
writeFileSync(build, readFileSync(build, 'utf8').replace(/^(\s*version\s*=\s*Version\(")[^"]+("\))/m,
  (_, before, after) => before + version + after));

if (edition === 'hq') {
  if (keyring) throw new Error('HQ builds never accept independent license keys.');
} else {
  if (!keyring) throw new Error('China builds require an approved RSA public keyring.');
  const keys = JSON.parse(readFileSync(keyring, 'utf8').replace(/^\uFEFF/, ''));
  const entries = Object.entries(keys);
  if (entries.length === 0 || entries.length > 32) throw new Error('Invalid public keyring size.');
  for (const [id, der] of entries) {
    if (!/^[\w.-]{1,120}$/.test(id) || typeof der !== 'string' || !/^[A-Za-z0-9+/=]+$/.test(der)) {
      throw new Error('Expected named DER public keys.');
    }
    const key = createPublicKey({ key: Buffer.from(der, 'base64'), format: 'der', type: 'spki' });
    if (key.asymmetricKeyType !== 'rsa' || key.asymmetricKeyDetails.modulusLength !== 3072) {
      throw new Error('Expected RSA 3072-bit public keys.');
    }
  }
  writeFileSync(join(stage, pod, 'res', 'license-keys.json'), JSON.stringify(Object.fromEntries(entries)) + '\n');
}
