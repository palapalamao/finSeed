import assert from 'node:assert/strict';
import {mkdtempSync, mkdirSync, writeFileSync, rmSync, unlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {basename, dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import test from 'node:test';

const checker = fileURLToPath(new URL('./check-versions.mjs', import.meta.url));

function withProject(run, directory = 'enerCubix.pod', version = '1.2.3') {
  const root = mkdtempSync(join(tmpdir(), 'enercubix-version-gate-'));
  const write = (path, value) => writeFileSync(join(root, path), typeof value === 'string' ? value : JSON.stringify(value));
  mkdirSync(join(root, directory, 'ts'), {recursive: true});
  write('package.json', {version});
  write(`${directory}/build.fan`, `// version = Version("9.9.9")\nversion = Version("${version}")\n`);
  write(`${directory}/ts/package.json`, {version});
  write(`${directory}/ts/package-lock.json`, {version, lockfileVersion: 3, packages: {'': {version}}});
  const check = () => spawnSync(process.execPath, [checker, root], {
    encoding: 'utf8', env: {...process.env, GITHUB_OUTPUT: ''},
  });
  try { run({root, write, check, directory}); }
  finally {
    assert.equal(dirname(resolve(root)), resolve(tmpdir()));
    assert.ok(basename(root).startsWith('enercubix-version-gate-'));
    rmSync(root, {recursive: true, force: true});
  }
}

test('accepts matching versions and ignores a commented version', () => withProject(({check}) => {
  const result = check();
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /1\.2\.3/);
}));

test('accepts the committed legacy source directory', () => withProject(({check}) => {
  assert.equal(check().status, 0);
}, 'finSeed.pod'));

test('accepts four-component Fantom versions and JSON with a BOM', () => withProject(({check, write}) => {
  write('package.json', '\ufeff{"version":"1.2.3.4"}');
  assert.equal(check().status, 0);
}, 'enerCubix.pod', '1.2.3.4'));

for (const target of ['package.json', 'build.fan', 'ui', 'lock', 'lock-root']) {
  test(`rejects version drift in ${target}`, () => withProject(({write, check, directory}) => {
    if (target === 'package.json') write('package.json', {version: '9.9.9'});
    if (target === 'build.fan') write(`${directory}/build.fan`, 'version = Version("9.9.9")');
    if (target === 'ui') write(`${directory}/ts/package.json`, {version: '9.9.9'});
    if (target === 'lock' || target === 'lock-root') write(`${directory}/ts/package-lock.json`, {
      version: target === 'lock' ? '9.9.9' : '1.2.3',
      packages: {'': {version: target === 'lock-root' ? '9.9.9' : '1.2.3'}},
    });
    assert.notEqual(check().status, 0, 'A mismatched version must stop the check');
  }));
}

test('rejects missing release metadata', () => withProject(({root, directory, check}) => {
  unlinkSync(join(root, directory, 'ts/package-lock.json'));
  assert.notEqual(check().status, 0);
}));

test('rejects ambiguous source directories', () => withProject(({root, check}) => {
  mkdirSync(join(root, 'finSeed.pod'));
  assert.notEqual(check().status, 0);
}));

test('rejects a missing lockfile root-package version', () => withProject(({write, directory, check}) => {
  write(`${directory}/ts/package-lock.json`, {version: '1.2.3', packages: {}});
  assert.notEqual(check().status, 0);
}));
