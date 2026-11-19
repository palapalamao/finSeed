import { randomBytes, scrypt as deriveKey, timingSafeEqual } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { promisify } from 'node:util';
import { IssuerError } from './license.mjs';

const scrypt = promisify(deriveKey);
const accountPattern = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const dummySalt = randomBytes(16);
const dummyHash = randomBytes(32);
const pageSize = 50;
const summary = 'license_id AS licenseId, type, host_id AS hostId, not_before AS notBefore, expires_at AS expiresAt, ' +
  'issued_at AS issuedAt, customer, note, issuer, previous_license_id AS previousLicenseId, action';
const schema = [
  'PRAGMA foreign_keys = ON;',
  'PRAGMA busy_timeout = 5000;',
  'CREATE TABLE IF NOT EXISTS accounts (',
  '  username TEXT PRIMARY KEY, salt BLOB NOT NULL, password_hash BLOB NOT NULL, revision INTEGER NOT NULL',
  ') STRICT;',
  'CREATE TABLE IF NOT EXISTS licenses (',
  '  license_id TEXT PRIMARY KEY, type TEXT NOT NULL, host_id TEXT, not_before TEXT NOT NULL, expires_at TEXT NOT NULL,',
  '  issued_at TEXT NOT NULL, customer TEXT NOT NULL, note TEXT NOT NULL, issuer TEXT NOT NULL,',
  '  previous_license_id TEXT REFERENCES licenses(license_id), action TEXT NOT NULL,',
  '  request_id TEXT NOT NULL, request_json TEXT NOT NULL, artifact TEXT NOT NULL,',
  '  UNIQUE (issuer, request_id),',
  "  CHECK ((type = 'host' AND host_id IS NOT NULL) OR (type = 'training' AND host_id IS NULL))",
  ') STRICT;',
  'CREATE INDEX IF NOT EXISTS licenses_by_issued_at ON licenses(issued_at DESC, license_id DESC);',
].join('\n');

export function openIssuerStore(dbPath) {
  const db = new DatabaseSync(dbPath);
  try { db.exec(schema); }
  catch (error) { db.close(); throw error; }
  const account = db.prepare('SELECT * FROM accounts WHERE username = ?');
  const get = db.prepare('SELECT ' + summary + ' FROM licenses WHERE license_id = ?');
  const getFile = db.prepare('SELECT artifact FROM licenses WHERE license_id = ?');
  const getRequest = db.prepare('SELECT license_id, request_json FROM licenses WHERE issuer = ? AND request_id = ?');
  const search = "instr(lower(customer || ' ' || coalesce(host_id,'') || ' ' || license_id), lower(?)) > 0";
  const list = db.prepare('SELECT ' + summary + ' FROM licenses WHERE ' + search + ' ORDER BY issued_at DESC, license_id DESC LIMIT ? OFFSET ?');
  const count = db.prepare('SELECT count(*) AS total FROM licenses WHERE ' + search);
  const insert = db.prepare([
    'INSERT INTO licenses (license_id,type,host_id,not_before,expires_at,issued_at,customer,note,issuer,',
    'previous_license_id,action,request_id,request_json,artifact) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
  ].join(' '));
  return {
    async setAccount(name, password) {
      if (typeof name !== 'string' || !accountPattern.test(name) ||
        typeof password !== 'string' || password.length < 12 || password.length > 256) {
        throw new Error('Use a lowercase account name and a password of 12 to 256 characters');
      }
      const salt = randomBytes(16);
      const passwordHash = await scrypt(password, salt, 32);
      db.prepare([
        'INSERT INTO accounts (username,salt,password_hash,revision) VALUES (?,?,?,1)',
        'ON CONFLICT(username) DO UPDATE SET salt=excluded.salt,password_hash=excluded.password_hash,revision=accounts.revision+1',
      ].join(' ')).run(name, salt, passwordHash);
    },
    async authenticate(name, password) {
      if (typeof name !== 'string' || typeof password !== 'string' || name.length > 64 || password.length > 256) {
        return null;
      }
      const row = account.get(name);
      const hash = await scrypt(password, row?.salt ?? dummySalt, 32);
      const matches = timingSafeEqual(hash, row?.password_hash ?? dummyHash);
      return matches && row ? { username: row.username, revision: row.revision } : null;
    },
    accountRevision: (name) => account.get(name)?.revision,
    issue(input, username, signer, now) {
      const requestJson = JSON.stringify(input);
      db.exec('BEGIN IMMEDIATE');
      try {
        const existing = getRequest.get(username, input.requestId);
        if (existing) {
          if (existing.request_json !== requestJson) throw new IssuerError('requestConflict', 409);
          const record = get.get(existing.license_id);
          db.exec('COMMIT');
          return { record, created: false };
        }
        let action = 'issue';
        if (input.previousLicenseId) {
          const previous = get.get(input.previousLicenseId);
          if (!previous || previous.type !== input.type) throw new IssuerError('invalidPreviousLicense');
          action = previous.hostId === input.hostId ? 'renewal' : 'reissue';
        }
        const signed = signer.signLicense(input, now);
        insert.run(signed.licenseId, input.type, input.hostId, input.notBefore, input.expiresAt, signed.issuedAt,
          input.customer, input.note, username, input.previousLicenseId, action, input.requestId, requestJson, signed.file);
        const record = get.get(signed.licenseId);
        db.exec('COMMIT');
        return { record, created: true };
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
    },
    list(query, page) {
      return { items: list.all(query, pageSize, (page - 1) * pageSize), page, pageSize, total: count.get(query).total };
    },
    get: (id) => get.get(id),
    file: (id) => getFile.get(id)?.artifact,
    close: () => db.close(),
  };
}
