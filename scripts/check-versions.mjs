import {appendFileSync, existsSync, readFileSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(process.argv[2] || join(dirname(fileURLToPath(import.meta.url)), '..'));
const json = path => JSON.parse(readFileSync(join(root, path), 'utf8').replace(/^\ufeff/, ''));

try {
  const directories = ['enerCubix.pod', 'finSeed.pod'].filter(path => existsSync(join(root, path)));
  if (directories.length !== 1) throw new Error('Expected exactly one source directory: enerCubix.pod or finSeed.pod');
  const source = directories[0];
  const ui = `${source}/ts`;
  const podVersion = readFileSync(join(root, source, 'build.fan'), 'utf8')
    .match(/^\s*version\s*=\s*Version\("([^"]+)"\)/m)?.[1];
  const lock = json(`${ui}/package-lock.json`);
  const versions = {
    'package.json': json('package.json').version,
    [`${source}/build.fan`]: podVersion,
    [`${ui}/package.json`]: json(`${ui}/package.json`).version,
    [`${ui}/package-lock.json`]: lock.version,
    [`${ui}/package-lock.json packages[""]`]: lock.packages?.['']?.version,
  };
  const expected = versions['package.json'];
  if (typeof expected !== 'string' || !/^\d+(?:\.\d+){2,3}$/.test(expected)) {
    throw new Error('Root version must have three or four numeric components');
  }
  const mismatches = Object.entries(versions).filter(([, version]) => version !== expected);
  if (mismatches.length) throw new Error(`Version mismatch (expected ${expected}):\n${mismatches
    .map(([path, version]) => `  ${path}: ${version ?? 'missing'}`).join('\n')}`);
  console.log(`版本一致 / Versions match: ${expected} (${source})`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `ui_dir=${ui}\n`);
} catch (error) {
  console.error(`版本检查失败 / Version check failed: ${error.message}`);
  process.exitCode = 1;
}
