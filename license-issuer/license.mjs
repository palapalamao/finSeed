import { constants, createPrivateKey, createPublicKey, randomUUID, sign } from 'node:crypto';

export const product = 'enerCubix';
export const idPattern = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;

export class IssuerError extends Error {
  constructor(code, status = 400) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

export function objectInput(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new IssuerError('invalidInput');
  return value;
}

export function hostId(value) {
  // Keep case and the FIN representation. The server that issued the request
  // decides whether a machine code uses the YH or HID format.
  if (typeof value !== 'string' || !/^[!-~]{1,512}$/.test(value.trim())) {
    throw new IssuerError('invalidHostId');
  }
  return value.trim();
}

function utcTime(value, code) {
  if (typeof value !== 'string') throw new IssuerError(code);
  const parts = /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,9}))?Z$/.exec(value);
  if (!parts) throw new IssuerError(code);
  const canonical = parts[1] + '.' + (parts[2] ?? '').padEnd(3, '0').slice(0, 3) + 'Z';
  const timestamp = Date.parse(canonical);
  if (!Number.isFinite(timestamp) || new Date(timestamp).toISOString() !== canonical) throw new IssuerError(code);
  return canonical;
}

export function parseActivationRequest(file) {
  const input = objectInput(file);
  if (input.version !== 1 || input.product !== product ||
    Object.keys(input).some(key => !['version', 'product', 'hostId', 'requestedAt'].includes(key))) {
    throw new IssuerError('invalidRequestFile');
  }
  return {
    hostId: hostId(input.hostId),
    requestedAt: utcTime(input.requestedAt, 'invalidRequestFile'),
  };
}

function optionalText(value, limit) {
  if (value === undefined) return '';
  if (typeof value !== 'string' || value.length > limit || /\u0000/.test(value)) throw new IssuerError('invalidInput');
  return value.trim();
}

export function normalizeIssue(body, now) {
  const input = objectInput(body);
  const fields = ['type', 'hostId', 'notBefore', 'expiresAt', 'customer', 'note', 'previousLicenseId', 'requestId'];
  if (Object.keys(input).some(key => !fields.includes(key)) || typeof input.requestId !== 'string' || !idPattern.test(input.requestId)) {
    throw new IssuerError('invalidInput');
  }
  if (input.type !== 'host' && input.type !== 'training') throw new IssuerError('invalidLicenseType');
  if (input.type === 'training' && Object.hasOwn(input, 'hostId')) throw new IssuerError('trainingHostId');
  const notBefore = utcTime(input.notBefore, 'invalidPeriod');
  const expiresAt = utcTime(input.expiresAt, 'invalidPeriod');
  if (expiresAt <= notBefore || Date.parse(expiresAt) <= now) throw new IssuerError('invalidPeriod');
  const previousLicenseId = input.previousLicenseId ?? null;
  if (previousLicenseId !== null && (typeof previousLicenseId !== 'string' || !idPattern.test(previousLicenseId))) {
    throw new IssuerError('invalidPreviousLicense');
  }
  return {
    type: input.type, hostId: input.type === 'host' ? hostId(input.hostId) : null,
    notBefore, expiresAt, customer: optionalText(input.customer, 120), note: optionalText(input.note, 500),
    previousLicenseId, requestId: input.requestId,
  };
}

export function makeSigner(keyId, key) {
  if (typeof keyId !== 'string' || !/^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$/.test(keyId)) throw new Error('Invalid issuer key ID');
  const privateKey = key?.type === 'private' ? key : createPrivateKey(key);
  if (privateKey.asymmetricKeyType !== 'rsa' || privateKey.asymmetricKeyDetails.modulusLength !== 3072) {
    throw new Error('An RSA 3072-bit private key is required');
  }
  const publicKey = createPublicKey(privateKey).export({ type: 'spki', format: 'der' });
  return {
    keyring: { [keyId]: publicKey.toString('base64') },
    signLicense(input, now) {
      const payload = {
        version: 1, product, type: input.type, licenseId: randomUUID(),
        issuedAt: new Date(now).toISOString(), notBefore: input.notBefore, expiresAt: input.expiresAt,
      };
      if (input.type === 'host') payload.hostId = input.hostId;
      const bytes = Buffer.from(JSON.stringify(payload), 'utf8');
      const signature = sign('sha256', bytes, { key: privateKey, padding: constants.RSA_PKCS1_PADDING });
      const file = JSON.stringify({ keyId, payload: bytes.toString('base64'), signature: signature.toString('base64') }, null, 2) + '\n';
      return { licenseId: payload.licenseId, issuedAt: payload.issuedAt, file };
    },
  };
}
