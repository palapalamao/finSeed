import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { readFileSync, statSync } from 'node:fs';
import { createServer } from 'node:https';
import { isAbsolute, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { IssuerError, idPattern, makeSigner, normalizeIssue, objectInput, parseActivationRequest } from './license.mjs';
import { openIssuerStore } from './store.mjs';

const cookieName = '__Host-enercubix-issuer';
const sessionSeconds = 8 * 60 * 60;
const loginWindow = 10 * 60 * 1000;
const maxBody = 16 * 1024;
const assets = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/app.js': ['app.js', 'text/javascript; charset=utf-8'],
  '/style.css': ['style.css', 'text/css; charset=utf-8'],
};

function secureHeaders(res) {
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Content-Security-Policy', "default-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'");
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Strict-Transport-Security', 'max-age=31536000');
  res.setHeader('X-Content-Type-Options', 'nosniff');
}

function json(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body));
}

function safeEqual(left, right) {
  const a = Buffer.from(left ?? '');
  const b = Buffer.from(right ?? '');
  return a.length === b.length && timingSafeEqual(a, b);
}

async function readBody(req) {
  if (req.headers['content-type']?.split(';', 1)[0].trim().toLowerCase() !== 'application/json') {
    throw new IssuerError('invalidContentType', 415);
  }
  if (Number(req.headers['content-length']) > maxBody) throw new IssuerError('tooLarge', 413);
  const chunks = [];
  let size = 0;
  for await (const chunk of req.iterator({ destroyOnReturn: false })) {
    size += chunk.length;
    if (size > maxBody) throw new IssuerError('tooLarge', 413);
    chunks.push(chunk);
  }
  let input;
  try { input = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))); }
  catch { throw new IssuerError('invalidInput'); }
  return objectInput(input);
}

function sessionCookie(value, seconds) {
  return cookieName + '=' + value + '; Path=/; Max-Age=' + seconds + '; HttpOnly; Secure; SameSite=Strict';
}

export function createIssuerHandler({ origin, store, privateKey, keyId, now = Date.now }) {
  const signer = makeSigner(keyId, privateKey);
  const sessionKey = randomBytes(32);
  const sessions = new Map();
  const loginAttempts = new Map();
  let concurrentLogins = 0;
  const mac = (id) => createHmac('sha256', sessionKey).update(id).digest('base64url');

  function readSession(req) {
    const cookie = req.headers.cookie?.split(';').map(value => value.trim()).find(value => value.startsWith(cookieName + '='));
    const parts = cookie?.slice(cookieName.length + 1).split('.');
    if (parts?.length !== 2 || !/^[a-f0-9]{64}$/.test(parts[0]) || !safeEqual(parts[1], mac(parts[0]))) return null;
    const session = sessions.get(parts[0]);
    if (!session) return null;
    if (session.expiresAt <= now() || store.accountRevision(session.username) !== session.revision) {
      sessions.delete(parts[0]);
      return null;
    }
    return { id: parts[0], ...session };
  }

  function limitLogin(req, res) {
    const timestamp = now();
    const address = req.socket.remoteAddress ?? 'local';
    for (const [ip, entry] of loginAttempts) if (entry.until <= timestamp) loginAttempts.delete(ip);
    const entry = loginAttempts.get(address) ?? { count: 0, until: timestamp + loginWindow };
    if (entry.count >= 8 || loginAttempts.size >= 4096 || concurrentLogins >= 4) {
      res.setHeader('Retry-After', Math.max(1, Math.ceil((entry.until - timestamp) / 1000)));
      throw new IssuerError('rateLimited', 429);
    }
    entry.count++;
    loginAttempts.set(address, entry);
  }

  async function login(req, res) {
    const input = await readBody(req);
    limitLogin(req, res);
    let user;
    concurrentLogins++;
    try { user = await store.authenticate(input.username, input.password); }
    finally { concurrentLogins--; }
    if (!user) throw new IssuerError('invalidCredentials', 401);
    const timestamp = now();
    for (const [id, session] of sessions) if (session.expiresAt <= timestamp) sessions.delete(id);
    const old = readSession(req);
    if (old) sessions.delete(old.id);
    if (sessions.size >= 1024) throw new IssuerError('rateLimited', 429);
    const id = randomBytes(32).toString('hex');
    const csrf = randomBytes(32).toString('base64url');
    sessions.set(id, { ...user, csrf, expiresAt: timestamp + sessionSeconds * 1000 });
    res.setHeader('Set-Cookie', sessionCookie(id + '.' + mac(id), sessionSeconds));
    return json(res, 200, { username: user.username, csrf });
  }

  return async function handle(req, res) {
    secureHeaders(res);
    try {
      const url = new URL(req.url, origin);
      const { pathname } = url;
      const asset = Object.hasOwn(assets, pathname) ? assets[pathname] : null;
      if (req.method === 'GET' && asset) {
        const [name, type] = asset;
        const bytes = readFileSync(new URL('./public/' + name, import.meta.url));
        res.writeHead(200, { 'Content-Type': type });
        res.end(bytes);
        return;
      }
      if (!pathname.startsWith('/api/')) throw new IssuerError('notFound', 404);
      const posting = req.method === 'POST';
      if (posting && req.headers.origin !== origin) throw new IssuerError('forbidden', 403);
      if (posting && pathname === '/api/login') return await login(req, res);

      const session = readSession(req);
      if (!session) throw new IssuerError('loginRequired', 401);
      if (posting && !safeEqual(req.headers['x-csrf-token'], session.csrf)) throw new IssuerError('forbidden', 403);
      if (posting && pathname === '/api/logout') {
        await readBody(req);
        sessions.delete(session.id);
        res.setHeader('Set-Cookie', sessionCookie('', 0));
        return json(res, 200, {});
      }
      if (req.method === 'GET' && pathname === '/api/session') {
        return json(res, 200, { username: session.username, csrf: session.csrf });
      }
      if (posting && pathname === '/api/requests/parse') {
        const input = await readBody(req);
        return json(res, 200, parseActivationRequest(input.requestFile));
      }
      if (posting && pathname === '/api/licenses') {
        const body = await readBody(req);
        const timestamp = now();
        const { record, created } = store.issue(normalizeIssue(body, timestamp), session.username, signer, timestamp);
        return json(res, created ? 201 : 200, record);
      }
      if (req.method === 'GET' && pathname === '/api/licenses') {
        const page = Number(url.searchParams.get('page') ?? '1');
        const query = (url.searchParams.get('q') ?? '').trim();
        if (!Number.isInteger(page) || page < 1 || page > 1_000_000 || query.length > 120) throw new IssuerError('invalidInput');
        return json(res, 200, store.list(query, page));
      }
      const fileId = /^\/api\/licenses\/([^/]+)\/file$/.exec(pathname)?.[1];
      if (req.method === 'GET' && fileId && idPattern.test(fileId)) {
        const file = store.file(fileId);
        if (file === undefined) throw new IssuerError('notFound', 404);
        res.writeHead(200, {
          'Content-Type': 'application/json; charset=utf-8',
          'Content-Disposition': 'attachment; filename="enercubix-' + fileId + '.enercubix-license"',
        });
        return res.end(file);
      }
      throw new IssuerError('notFound', 404);
    } catch (error) {
      if (!req.complete) {
        res.setHeader('Connection', 'close');
        req.resume();
      }
      if (error instanceof IssuerError) return json(res, error.status, { error: error.code });
      // The signing request and any credentials belong to the issuer account.
      // Avoid copying them into process logs.
      console.error('EnerCubix issuer request failed');
      return json(res, 500, { error: 'internalError' });
    }
  };
}

export function absoluteEnv(env, name) {
  const value = env[name];
  if (!value || !isAbsolute(value)) throw new Error(name + ' must be an absolute path');
  return value;
}

function run(env) {
  const url = new URL(env.ISSUER_ORIGIN);
  if (url.protocol !== 'https:' || env.ISSUER_ORIGIN !== url.origin) {
    throw new Error('ISSUER_ORIGIN must be an HTTPS origin without a path or trailing slash');
  }
  const port = Number(env.ISSUER_PORT ?? (url.port || '443'));
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid ISSUER_PORT');
  const privateKey = readFileSync(absoluteEnv(env, 'ISSUER_PRIVATE_KEY_FILE'));
  const tls = {
    key: readFileSync(absoluteEnv(env, 'ISSUER_TLS_KEY_FILE')),
    cert: readFileSync(absoluteEnv(env, 'ISSUER_TLS_CERT_FILE')),
    minVersion: 'TLSv1.2', requestTimeout: 15000, headersTimeout: 10000, maxHeaderSize: 8192,
  };
  const dbPath = absoluteEnv(env, 'ISSUER_DB_PATH');
  if (!statSync(dbPath, { throwIfNoEntry: false })?.isFile()) throw new Error('Create an issuer account with the CLI before starting the service');
  const store = openIssuerStore(dbPath);
  try {
    const handler = createIssuerHandler({ origin: url.origin, store, privateKey, keyId: env.ISSUER_KEY_ID });
    const server = createServer(tls, handler);
    server.maxConnections = 128;
    server.listen(port, env.ISSUER_BIND ?? '127.0.0.1', () => console.log('EnerCubix issuer listening on ' + url.origin));
    for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, () => server.close(() => store.close()));
  } catch (error) {
    store.close();
    throw error;
  }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) run(process.env);
