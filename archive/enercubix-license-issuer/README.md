# EnerCubix license issuer

[简体中文](README.zh-CN.md)

The issuer is a standalone service for signing EnerCubix activation files. It runs on Node.js 22.22 and uses SQLite for issuer accounts and signed artifacts. FIN customers can import the files offline.

## Set up the issuer

Keep the SQLite database, signing key, and TLS key in a directory outside the repository. On Windows, configure the directory's NTFS access for the account that runs the issuer. Use a separate directory, signing key and key ID for testing.

Set these environment variables before running the CLI and starting the service.

| Variable | Value |
|---|---|
| `ISSUER_DB_PATH` | Absolute path to the SQLite database |
| `ISSUER_PRIVATE_KEY_FILE` | Absolute path to the RSA 3072-bit signing key in PKCS#8 PEM format |
| `ISSUER_KEY_ID` | Signing key identifier included in the license envelope |
| `ISSUER_TLS_CERT_FILE` | Absolute path to the HTTPS certificate chain in PEM format |
| `ISSUER_TLS_KEY_FILE` | Absolute path to the HTTPS private key in PEM format |
| `ISSUER_ORIGIN` | HTTPS origin used by the browser, with no path or trailing slash |
| `ISSUER_BIND` | Listener address. Defaults to `127.0.0.1` |
| `ISSUER_PORT` | Listener port. Defaults to the origin's port or 443 |

Create the signing key once. The command creates a new file and fails if the path already exists. Create an issuer account with a masked PowerShell 7 prompt.

```powershell
node license-issuer/cli.mjs create-key
Read-Host 'Issuer account password' -MaskInput | node license-issuer/cli.mjs account operator
node license-issuer/cli.mjs export-key
node license-issuer/server.mjs
```

Account names use lowercase letters, digits, dots, underscores and hyphens. Passwords must have 12 to 256 characters. Running the account command again changes that account's password and invalidates its prior sessions. The export command prints the public keyring as JSON. Provide that JSON to the Pod build to trust licenses from this signer. The server uses HTTPS with the configured certificate. Run one issuer process for each database.

## Issue and renew

1. Sign in. For a **machine-bound** license, paste the FIN Host ID or select the activation request exported by EnerCubix. For a **training** license, select Training. Training licenses use the signed validity period on any FIN host.
2. Enter the start and expiry in the displayed browser time zone. Review the UTC values before signing. The expiry is the first instant at which the license is no longer valid.
3. Choose **Sign license**. The server records the account and issuance time and saves the signed file before offering it for download.
4. Provide the downloaded `.enercubix-license` file to the FIN host superuser. They import it in **Settings → License management**. Import a license during its validity period.
5. Use **Issuance history** to download the original file or renew it. To reissue a machine-bound license for a different host, enter the new Host ID after selecting **Renew or reissue**. The new record links to the previous one.

Back up the SQLite database and signing key through the issuer's protected storage. Stop the issuer before copying the database so the backup contains complete transactions.

## File format and verification

An activation request contains `version` (1), `product` (`enerCubix`), `hostId` and `requestedAt`. A signed license contains `keyId`, `payload` and `signature`. Both payload and signature use standard Base64. The signature covers the exact UTF-8 JSON payload using RSA PKCS#1 v1.5 and SHA-256. The signed payload contains `version`, `product`, `type`, `licenseId`, `issuedAt`, `notBefore` and `expiresAt`. A `host` license also contains `hostId`. A `training` license omits `hostId`. All signed timestamps use UTC ISO 8601.

The keyring export maps key IDs to Base64 DER SubjectPublicKeyInfo public keys.

```powershell
node --test license-issuer/issuer.test.mjs
```
