# YubiHSM 2 Concepts

Background concepts referenced by `SKILL.md`. Read when you need to construct capability strings, design domain layouts, or reason about session/object semantics.

## Objects

All persistent data in the HSM. 9 types:

| Type | Purpose |
|---|---|
| authentication-key | Opens authenticated sessions |
| asymmetric-key | RSA / ECDSA / EdDSA private keys |
| symmetric-key | AES keys (firmware 2.3.1+) |
| wrap-key | Encrypts other objects for export/backup (AES-CCM) |
| hmac-key | HMAC signing keys |
| opaque | Arbitrary data (X.509 certs, blobs) |
| template | SSH certificate templates |
| otp-aead-key | OATH-HOTP/TOTP and Yubico OTP encryption keys |
| public-wrap-key | Public half of an RSA wrap pair (asymmetric wrap, firmware 2.4+) |

- Identified by `(Type, ID)` pair — the same ID can be reused across types.
- Max 256 objects total; max 126 KB total storage.
- IDs `0x0000` and `0xFFFF` are reserved. Pass `0` to auto-assign on create.
- **Every object type is exportable under wrap**, including authentication keys. Auth keys CAN be backed up via wrap keys — do not skip them during backup planning.

## Sessions

All operations require an authenticated session. Opened with an authentication key.

- Max 16 concurrent sessions.
- 30-second inactivity timeout — idle sessions are closed automatically.
- CLI mode (`-a <action>`) handles open/close per invocation. The REPL holds a session for its lifetime.

## Domains

16 logical partitions, numbered 1–16. Encoded as a 16-bit bitmask.

- Every object belongs to one or more domains.
- An auth key can only access objects sharing at least one domain.
- Use domains to isolate applications or roles (e.g. domain 1 = code-signing, domain 2 = TLS, domain 3 = backup).

## Capabilities

64-bit flags controlling permitted operations. Full table in `capabilities-ref.md`.

**Both the auth key AND the target object must possess the required capability.** Example: to sign with ECDSA, the auth key needs `sign-ecdsa` AND the asymmetric key needs `sign-ecdsa`.

### Delegated Capabilities

Only present on auth keys and wrap keys. Upper bound on capabilities assignable to newly created or imported objects.

If you create a key via an auth key, the new key's capabilities cannot exceed that auth key's delegated capabilities. Plan delegated caps to be a superset of every cap the auth key will ever need to grant downstream.

## Algorithms

Specify crypto operations. See `capabilities-ref.md` for the full list. Most common:

| Algorithm | Used for |
|---|---|
| `ecp256` / `ecp384` / `ecp521` | ECDSA, ECDH |
| `ed25519` | EdDSA |
| `rsa2048` / `rsa3072` / `rsa4096` | RSA sign/decrypt |
| `aes128` / `aes192` / `aes256` | AES encrypt/decrypt |
| `aes128-ccm-wrap` / `aes192-ccm-wrap` / `aes256-ccm-wrap` | Wrap keys |
| `hmac-sha1` / `hmac-sha256` / `hmac-sha384` / `hmac-sha512` | HMAC |

## Audit Log

Circular buffer holding 62 entries. Every operation appends one entry.

- Retrieve with `-a get-logs`.
- If `force-audit` device option is enabled and the log fills up, ALL operations except `session-open` and `get-logs` are blocked until the log is drained.
- Drain by calling `get-logs` then `set-log-index` to mark entries consumed.
