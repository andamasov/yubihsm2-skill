# YubiHSM 2 Operational Skill — Design Spec

## Overview

A Claude Code skill that operates YubiHSM 2 devices by executing `yubihsm-shell` commands via the Bash tool. The skill covers the full operational lifecycle: connector setup, provisioning, key management, cryptographic operations, backup/restore, and factory reset.

**Audience:** Beginners to intermediate HSM users. The skill includes a concepts primer and explains what each operation does before executing it.

**Scope:** Operational only. No SDK/PKCS#11/KSP integration (future work).

## Skill Type

Operational (rigid). Claude executes commands, not just displays them. Workflows are followed exactly, with confirmation gates before mutating or destructive operations.

## File Layout

```
yubishm2-skill/
  skills/
    yubihsm2/
      SKILL.md              # Main skill — concepts, execution model, workflows
      command-reference.md   # Full yubihsm-shell command syntax + examples
      capabilities-ref.md   # Capabilities, algorithms, domains lookup tables
  docs/
    superpowers/
      specs/
        2026-03-30-yubihsm2-skill-design.md   # This file
  README.md
  .gitignore
```

**Installation:**

```bash
# Personal use — symlink into Claude Code skills directory
ln -s ~/GitHub/yubishm2-skill/skills/yubihsm2 ~/.claude/skills/yubihsm2

# Distribution — clone and symlink
git clone <repo-url> ~/GitHub/yubishm2-skill
ln -s ~/GitHub/yubishm2-skill/skills/yubihsm2 ~/.claude/skills/yubihsm2
```

No build step. No dependencies. Pure markdown.

## Execution Model

### CLI Mode Only

All operations use one-shot CLI invocations:

```bash
yubihsm-shell \
  --connector "$YUBIHSM_CONNECTOR_URL" \
  --authkey "$YUBIHSM_AUTH_KEY_ID" \
  -p "$YUBIHSM_PASSWORD" \
  -a <action> [action-specific flags]
```

Interactive REPL mode is not used — Claude Code's Bash tool does not support interactive sessions.

### Credential Resolution

Order of resolution:

1. Check environment variables: `YUBIHSM_AUTH_KEY_ID`, `YUBIHSM_PASSWORD`, `YUBIHSM_CONNECTOR_URL`
2. If any are missing, prompt the user
3. `YUBIHSM_CONNECTOR_URL` defaults to `http://127.0.0.1:12345` if unset and user confirms default

### Pre-Flight Checks

Before every workflow:

1. Verify `yubihsm-shell` is in PATH (`which yubihsm-shell`)
2. Verify connector is reachable (`curl -s http://<connector>/connector/status`)
3. Parse connector status for `status=OK`

### Risk-Level Classification

| Risk Level | Operations | Behavior |
|---|---|---|
| Read-only | list objects, get device-info, get storage-info, get log-entries, get pubkey, get objectinfo | Execute without confirmation |
| Mutating | generate keys, put auth keys, sign, encrypt, decrypt, set option, put opaque, put template | Describe what will happen, confirm once before executing |
| Destructive | delete object, factory reset, delete default auth key | Explicit warning stating irreversibility, confirm before executing |

Factory reset requires double confirmation.

## SKILL.md Structure

### 1. Frontmatter

```yaml
name: yubihsm2
description: Operate YubiHSM 2 devices — provisioning, key management, crypto operations, backup/restore via yubihsm-shell
```

**Trigger conditions:** User mentions YubiHSM, yubihsm-shell, yubihsm-connector, HSM key management, hardware security module operations.

### 2. Execution Model

Documents the CLI-mode-only pattern, credential resolution, pre-flight checks, and risk classification as specified above.

### 3. Concepts Primer

Concise (~300 words) covering:

- **Objects** — All persistent data in the HSM. 9 types: authentication-key, asymmetric-key, symmetric-key, wrap-key, hmac-key, opaque, template, otp-aead-key, public-wrap-key. Each identified by (Type, ID) pair. Max 256 objects, 126 KB total.
- **Sessions** — All operations happen inside authenticated sessions. Opened with an authentication key. Max 16 concurrent, 30-second inactivity timeout.
- **Domains** — 16 logical partitions. Objects and auth keys belong to one or more domains. An auth key can only access objects sharing at least one domain.
- **Capabilities** — 64-bit flags controlling what operations an object supports. Both the auth key and target object must have the required capability for an operation to succeed.
- **Delegated Capabilities** — Only on auth keys and wrap keys. Limit what capabilities can be assigned to newly created or imported objects. Act as an upper bound filter.
- **Algorithms** — Specify cryptographic operations. RSA (2048/3072/4096), EC (P224/P256/P384/P521, brainpool, ed25519), HMAC (SHA1/256/384/512), AES (128/192/256).

### 4. Connector Setup Workflow

Claude executes:

1. Detect OS (Linux distro or macOS)
2. Install `yubihsm-connector` and `yubihsm-shell` via appropriate package manager
3. Write udev rules (Linux) for USB device access
4. Configure connector (listening address, optional TLS)
5. Start connector (systemd or direct invocation)
6. Verify status via HTTP endpoint

### 5. Operational Workflows

#### 5.1 Initial Provisioning

1. Open session with default auth key (ID 1, password `password`)
2. Create audit auth key — capabilities: `get-log-entries` only, all domains
3. Create operational auth key(s) — user specifies:
   - Label
   - Domains
   - Capabilities
   - Delegated capabilities
   - Password
4. Verify new auth keys work (open session with each)
5. **[Destructive]** Delete default auth key (ID 1) — warn that this is irreversible without the new keys
6. List objects to confirm final state

#### 5.2 Key Generation

1. Ask user: key type, algorithm, label, domains, capabilities
2. For asymmetric keys: ask if `exportable-under-wrap` is needed
3. Execute `yubihsm-shell -a generate-asymmetric-key` (or symmetric, hmac, wrap-key)
4. Capture returned object ID
5. Show object info to confirm

#### 5.3 Signing & Verification

1. Get object info to determine key type and algorithm
2. Execute appropriate sign command:
   - RSA: `sign pkcs1v1_5` or `sign pss`
   - EC: `sign ecdsa`
   - Ed25519: `sign eddsa`
   - HMAC: `sign hmac`
3. Output signature (base64 or to file)
4. For asymmetric keys: extract public key (`get pubkey`), provide OpenSSL verification command

#### 5.4 Encryption/Decryption

1. Get object info to determine key type
2. Execute appropriate command:
   - RSA: `decrypt pkcs1v1_5` or `decrypt oaep`
   - AES: `encrypt aescbc` / `decrypt aescbc` / `encrypt aesecb` / `decrypt aesecb`
3. Output result

#### 5.5 Backup & Restore

**Backup:**

1. Identify or generate wrap key — must have:
   - Capabilities: `export-wrapped`, `import-wrapped`
   - Domains: all domains containing objects to back up
   - Delegated capabilities: superset of all backed-up objects' capabilities
2. List all objects, flag any missing `exportable-under-wrap`
3. Export each eligible object (`get wrapped`), save as `.yhw` files
4. Warn user to secure the wrap key material

**Restore:**

1. Prompt for backup device connector URL
2. Import wrap key to backup device (`put wrap-key`)
3. Import all `.yhw` files (`put wrapped`)
4. List objects on backup device, compare against originals

#### 5.6 Factory Reset

1. Warn: destroys all non-factory objects, irreversible
2. Offer backup workflow if not already done
3. Double confirmation
4. Execute reset (software: `yubihsm-shell -a reset-device`; or instruct physical method: hold touch sensor 10 seconds). Note: verify exact action name via `yubihsm-shell --help` at runtime — documentation lists this as "RESET DEVICE" command.
5. Verify device returns to default state (open session with default key)

#### 5.7 Access Control Design

1. Ask user: how many roles/applications, what operations each needs
2. Propose domain layout and capability assignments
3. On approval, create auth keys with specified domains, capabilities, delegated capabilities
4. Verify by listing objects and showing effective access per auth key

#### 5.8 Audit Log

1. Retrieve log entries (`get log-entries`)
2. Parse and display in human-readable format
3. Flag any anomalies (failed auth attempts, unexpected commands)

### 6. Error Handling

Map error codes to causes and recovery actions:

| Code | Name | Likely Cause | Recovery |
|---|---|---|---|
| 0x04 | AUTHENTICATION_FAILED | Wrong auth key ID or password | Verify credentials, check auth key exists |
| 0x05 | SESSIONS_FULL | 16 sessions already open | Wait for timeout or close unused sessions |
| 0x07 | STORAGE_FAILED | 256 objects or 126 KB limit reached | Delete unused objects |
| 0x09 | INSUFFICIENT_PERMISSIONS | Auth key lacks required capability or domain | Check capabilities and domains on both auth key and target object |
| 0x0a | LOG_FULL | Audit log full + force-audit enabled | Retrieve and acknowledge log entries |
| 0x0b | OBJECT_NOT_FOUND | Wrong ID, wrong type, or domain mismatch | Verify object exists and shares domain with auth key |
| 0x11 | OBJECT_EXISTS | Object with same (Type, ID) already present | Use different ID or delete existing object first |

### 7. Reference File Pointers

- Read `command-reference.md` when exact syntax for a specific command is needed
- Read `capabilities-ref.md` when constructing capability/algorithm strings or planning access control

## command-reference.md Scope

Every `yubihsm-shell` command organized by category:

- **Session:** open, close, open_asym
- **Device:** blink, reset, get device-info, get storage-info, get device-pubkey
- **Key generation:** generate asymmetric, symmetric, hmackey, wrap-key, otpaeadkey
- **Object management:** put (all types), delete, list objects, get objectinfo
- **Crypto operations:** sign (pkcs1v1_5, pss, ecdsa, eddsa, hmac), decrypt (pkcs1v1_5, oaep, aescbc, aesecb), encrypt (aescbc, aesecb), derive ecdh, verify hmac
- **Wrapping:** get wrapped, put wrapped, get rsa_wrapped, put rsa-wrapped, wrap data, unwrap data
- **SSH/Attestation:** sign ssh-certificate, sign attestation-certificate, get/put template
- **OTP:** otp aead_create, otp decrypt, otp aead_randomize, otp aead_rewrap
- **Config:** change authkey, get/set option, get log-entries, set log-index, get pseudo-random
- **Utility:** echo, get opaque, put opaque, set informat, set outformat

Each entry: syntax, parameter types, one example.

## capabilities-ref.md Scope

Three tables:

1. **Capabilities** — name, hex value, which object types it applies to, brief description
2. **Algorithms** — name, hex value, key type, operation type
3. **Domains** — number (1-16), hex mask

Plus a section on delegated capabilities rules:
- Auth key delegated caps limit what caps new objects can receive
- Wrap key delegated caps limit what caps wrapped objects can have during import
- Effective capabilities = intersection of auth key caps and target object caps
