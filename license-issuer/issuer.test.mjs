import assert from 'node:assert/strict';
import { generateKeyPairSync, randomUUID, verify } from 'node:crypto';
import { once } from 'node:events';
import { mkdtemp, rm, rmdir } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { openIssuerStore } from './store.mjs';
import { createIssuerHandler } from './server.mjs';

const keys = generateKeyPairSync('rsa', { modulusLength: 3072 });
const password = 'test-account-password';
const now = () => Date.parse('2026-11-13T09:00:00.000Z');
const issueInput = (fields = {}) => ({
  requestId: randomUUID(), type: 'host', hostId: 'HID-EXAMPLE',
  notBefore: '2026-11-13T09:00:00.000Z', expiresAt: '2027-11-13T09:00:00.000Z',
  customer: 'Example customer', note: 'Example request', ...fields,
});

async function fixture(t, dbPath = ':memory:') {
  const store = openIssuerStore(dbPath);
  await store.setAccount('issuer', password);
  let handler;
  const server = createServer((req, res) => handler(req, res));
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const origin = `http://127.0.0.1:${server.address().port}`;
  handler = createIssuerHandler({ origin, store, privateKey: keys.privateKey, keyId: 'fixture', now });
  t.after(async () => {
    await new Promise(resolve => server.close(resolve));
    store.close();
  });
  async function request(path, options = {}) {
    const { body, cookie, csrf, requestOrigin = origin } = options;
    const headers = {};
    if (cookie) headers.Cookie = cookie;
    if (csrf) headers['X-CSRF-Token'] = csrf;
    if (body !== undefined) Object.assign(headers, { Origin: requestOrigin, 'Content-Type': 'application/json' });
    return fetch(origin + path, { method: body === undefined ? 'GET' : 'POST', headers, body: body === undefined ? undefined : JSON.stringify(body) });
  }
  async function login() {
    const res = await request('/api/login', { body: { username: 'issuer', password } });
    assert.equal(res.status, 200);
    const cookie = res.headers.get('set-cookie');
    assert.match(cookie, /HttpOnly/);
    assert.match(cookie, /Secure/);
    assert.match(cookie, /SameSite=Strict/);
    return { cookie: cookie.split(';')[0], csrf: (await res.json()).csrf };
  }
  return { store, request, login };
}

test('requires login, origin and CSRF and invalidates a logged-out session', async t => {
  const { request, login } = await fixture(t);
  assert.equal((await request('/api/licenses')).status, 401);
  assert.equal((await request('/api/login', {
    body: { username: 'issuer', password }, requestOrigin: 'https://untrusted.example',
  })).status, 403);
  const session = await login();
  assert.equal((await request('/api/licenses', { cookie: session.cookie + 'x' })).status, 401);
  assert.equal((await request('/api/licenses', { cookie: session.cookie, body: issueInput() })).status, 403);
  assert.equal((await request('/api/licenses', {
    ...session, body: issueInput(), requestOrigin: 'https://untrusted.example',
  })).status, 403);
  assert.equal((await request('/api/logout', { ...session, body: {} })).status, 200);
  assert.equal((await request('/api/licenses', session)).status, 401);
});

test('limits repeated failed logins', async t => {
  const { request } = await fixture(t);
  for (let i = 0; i < 8; i++) {
    assert.equal((await request('/api/login', { body: { username: 'issuer', password: 'incorrect password' } })).status, 401);
  }
  assert.equal((await request('/api/login', { body: { username: 'issuer', password } })).status, 429);
});

test('validates the exported request, training scope and license period on the server', async t => {
  const { request, login } = await fixture(t);
  const session = await login();
  const parseRequest = (requestFile) => request('/api/requests/parse', { ...session, body: { requestFile } });
  const valid = await parseRequest({ version: 1, product: 'finEnergy', hostId: 'HID-EXAMPLE', requestedAt: '2026-11-13T10:00:00.123456Z' });
  assert.equal(valid.status, 200);
  assert.equal((await valid.json()).hostId, 'HID-EXAMPLE');
  assert.equal((await parseRequest({ version: 1, product: 'wrong' })).status, 400);
  for (const fields of [
    { type: 'host', hostId: '' }, { type: 'training' }, { type: 'unexpected' },
    { expiresAt: '2026-11-13T09:00:00.000Z' },
    { notBefore: '2026-02-30T09:00:00.000Z' },
    { expiresAt: '2027-11-13T09:00:00+08:00' },
  ]) {
    assert.equal((await request('/api/licenses', { ...session, body: issueInput(fields) })).status, 400);
  }
});

test('signs machine-bound and time-only licenses, persists exact files and links renewals', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'finenergy-issuer-test-'));
  const dbPath = join(directory, 'issuer.sqlite');
  // Cleanup runs after the fixture closes its Windows file handles.
  const fixtureTest = { after: (cleanup) => t.after(async () => { await cleanup(); await rm(dbPath, { force: true }); await rmdir(directory); }) };
  const { request, login } = await fixture(fixtureTest, dbPath);
  const session = await login();
  async function issue(body, status = 201) {
    const res = await request('/api/licenses', { ...session, body });
    assert.equal(res.status, status);
    return res.json();
  }
  async function download(id) {
    const res = await request(`/api/licenses/${id}/file`, session);
    assert.equal(res.status, 200);
    assert.match(res.headers.get('content-disposition'), /attachment/);
    const file = await res.text();
    const { keyId, payload, signature } = JSON.parse(file);
    assert.equal(keyId, 'fixture');
    assert.ok(verify('sha256', Buffer.from(payload, 'base64'), keys.publicKey, Buffer.from(signature, 'base64')));
    return { file, payload: JSON.parse(Buffer.from(payload, 'base64')) };
  }
  const originalRequest = issueInput();
  const host = await issue(originalRequest);
  const repeat = await issue(originalRequest, 200);
  assert.equal(repeat.licenseId, host.licenseId);
  assert.equal((await request('/api/licenses', { ...session, body: { ...originalRequest, note: 'Different input' } })).status, 409);
  const hostFile = await download(host.licenseId);
  assert.equal(hostFile.payload.hostId, 'HID-EXAMPLE');
  assert.equal(hostFile.payload.type, 'host');
  assert.equal(hostFile.payload.version, 1);
  assert.equal(hostFile.payload.product, 'finEnergy');
  assert.equal(hostFile.payload.licenseId, host.licenseId);
  assert.equal(hostFile.payload.issuedAt, '2026-11-13T09:00:00.000Z');
  assert.equal(hostFile.payload.customer, undefined);
  const trainingInput = issueInput({ type: 'training' });
  delete trainingInput.hostId;
  const training = await issue(trainingInput);
  const trainingFile = await download(training.licenseId);
  assert.equal(trainingFile.payload.type, 'training');
  assert.equal(Object.hasOwn(trainingFile.payload, 'hostId'), false);
  assert.equal(trainingFile.payload.expiresAt, '2027-11-13T09:00:00.000Z');
  const renewed = await issue(issueInput({ previousLicenseId: host.licenseId, expiresAt: '2028-11-13T09:00:00.000Z' }));
  assert.equal(renewed.previousLicenseId, host.licenseId);
  assert.equal(renewed.action, 'renewal');
  const moved = await issue(issueInput({ previousLicenseId: host.licenseId, hostId: 'HID-MOVED' }));
  assert.equal(moved.action, 'reissue');
  assert.equal((await download(host.licenseId)).file, hostFile.file);
  const readBack = openIssuerStore(dbPath);
  try {
    assert.equal(readBack.file(host.licenseId), hostFile.file);
    assert.equal(readBack.get(host.licenseId).issuer, 'issuer');
    assert.equal(readBack.get(renewed.licenseId).previousLicenseId, host.licenseId);
  } finally { readBack.close(); }
});
