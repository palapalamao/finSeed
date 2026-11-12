import { generateKeyPairSync } from 'node:crypto';
import { closeSync, openSync, readFileSync, writeFileSync } from 'node:fs';
import { makeSigner } from './license.mjs';
import { openIssuerStore } from './store.mjs';
import { absoluteEnv } from './server.mjs';

async function readPassword() {
  const chunks = [];
  let size = 0;
  for await (const chunk of process.stdin) {
    size += chunk.length;
    if (size > 1024) throw new Error('Password input is too long');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8').replace(/\r?\n$/, '');
}

function prepareDatabase(path) {
  try { closeSync(openSync(path, 'wx', 0o600)); }
  catch (error) { if (error.code !== 'EEXIST') throw error; }
}

async function main([command, username, ...extra], env) {
  if (command === 'create-key' && username === undefined) {
    const path = absoluteEnv(env, 'ISSUER_PRIVATE_KEY_FILE');
    const { privateKey } = generateKeyPairSync('rsa', {
      modulusLength: 3072,
      privateKeyEncoding: { format: 'pem', type: 'pkcs8' },
    });
    writeFileSync(path, privateKey, { flag: 'wx', mode: 0o600 });
    console.log('Created a new RSA signing key');
  } else if (command === 'export-key' && username === undefined) {
    const key = readFileSync(absoluteEnv(env, 'ISSUER_PRIVATE_KEY_FILE'));
    const { keyring } = makeSigner(env.ISSUER_KEY_ID, key);
    console.log(JSON.stringify(keyring, null, 2));
  } else if (command === 'account' && username && !extra.length) {
    if (process.stdin.isTTY) throw new Error('Pipe the account password through standard input from a masked prompt');
    const password = await readPassword();
    const path = absoluteEnv(env, 'ISSUER_DB_PATH');
    prepareDatabase(path);
    const store = openIssuerStore(path);
    try { await store.setAccount(username, password); } finally { store.close(); }
    console.log('Saved issuer account');
  } else {
    throw new Error('Use create-key, export-key or account <username>');
  }
}

try { await main(process.argv.slice(2), process.env); }
catch (error) { console.error(error.message); process.exitCode = 1; }
