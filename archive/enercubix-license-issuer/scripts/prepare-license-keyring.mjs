import { createPublicKey } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';

const [input, output] = process.argv.slice(2);

try {
  const raw = readFileSync(input, 'utf8').replace(/^\uFEFF/, '');
  const keyring = JSON.parse(raw);
  if (!keyring || typeof keyring !== 'object' || Array.isArray(keyring)) {
    throw new Error('Expected a JSON object of public keys');
  }
  const entries = Object.entries(keyring);
  if (!entries.length || entries.length > 16) {
    throw new Error('Expected 1–16 public keys');
  }
  for (const [id, value] of entries) {
    if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$/.test(id) || typeof value !== 'string' || value.length > 1024) {
      throw new Error('Invalid public key ID or encoding');
    }
    const der = Buffer.from(value, 'base64');
    const key = createPublicKey({ key: der, type: 'spki', format: 'der' });
    if (key.asymmetricKeyType !== 'rsa' || key.asymmetricKeyDetails.modulusLength !== 3072 ||
        key.export({ type: 'spki', format: 'der' }).toString('base64') !== value) {
      throw new Error('Expected a canonical base64 RSA 3072-bit public key');
    }
  }
  writeFileSync(output, JSON.stringify(keyring) + '\n', { flag: 'wx' });
} catch (error) {
  console.error(`License keyring preparation failed: ${error.message}`);
  process.exitCode = 1;
}
