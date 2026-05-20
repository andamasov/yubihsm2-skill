---
name: yubihsm2
description: Use when operating a YubiHSM 2 device — provisioning, key generation, signing, encryption, backup/restore, factory reset, access control design, or any yubihsm-shell / yubihsm-connector task
---

# YubiHSM 2 Operations

Operate YubiHSM 2 hardware security modules by executing `yubihsm-shell` commands via Bash. This skill executes commands directly — it does not just display them.

**When to use this skill vs. the MCP server (`~/GitHub/yubihsm2-mcp`):** use the MCP server when an LLM client needs a persistent, typed tool surface (chat-based ops over many turns, two-profile auth split). Use this skill for one-off CLI ops, provisioning runs, scripted backups, air-gapped USB-direct work, or any case where shelling out is cheaper than running the MCP daemon. Both wrap the same `yubihsm-shell` semantics.

## Execution Model

### Transports

`yubihsm-shell --connector` accepts three forms:

| Form | Use when | Example |
|---|---|---|
| `https://HOST:PORT` | Remote HSM behind a connector daemon, TLS | `https://10.217.32.192:12345` (HSM-1 default) |
| `http://HOST:PORT` | Local connector daemon, no TLS | `http://127.0.0.1:12345` |
| `yhusb://[serial=NNNN]` | Direct USB on this host — **no connector daemon needed** | `yhusb://`, `yhusb://serial=0123456789` |

For HTTPS connectors, also pass `--cacert` with the connector CA cert (at `.claude/yubihsm-connector.crt` relative to the repo root for the default device set). For `http://` and `yhusb://`, no cacert applies.

### CLI Mode Only

All commands use one-shot invocations. Do NOT use interactive REPL mode.

```bash
yubihsm-shell \
  --connector "$YUBIHSM_CONNECTOR_URL" \
  --authkey "$YUBIHSM_AUTH_KEY_ID" \
  -p "$YUBIHSM_PASSWORD" \
  -a <action> [flags]
```

### Default Device

Unless the user specifies otherwise, all operations target **HSM-1 (primary)** at `https://10.217.32.192:12345`.

The device fleet:
| Device | Role | Connector URL | Status |
|---|---|---|---|
| HSM-1 | Primary (default) | https://10.217.32.192:12345 | Active |
| HSM-2 | Hot backup | https://10.217.32.191:12345 | Offline — pending physical reset |
| HSM-3 | Cold backup | https://10.217.72.234:12345 | Active |
| Local USB | Direct (provisioning, air-gapped ops) | `yhusb://` | Use when the HSM is plugged into this host |

### Credential Resolution

1. Check env vars: `YUBIHSM_AUTH_KEY_ID`, `YUBIHSM_PASSWORD`, `YUBIHSM_CONNECTOR_URL`
2. If `BW_SESSION` is set and `bw` CLI is available, try fetching from Bitwarden first (see below)
3. If still missing, prompt the user — do NOT assume defaults
4. `YUBIHSM_CONNECTOR_URL` defaults to `https://10.217.32.191:12345` (HSM-1) if user confirms

**Never assume auth key ID 1 / password "password" unless the user explicitly states they are using factory defaults.**

### Bitwarden Integration

HSM auth key passwords can be stored in and retrieved from Bitwarden using the `bw` CLI.

**Prerequisites:** `bw` and `jq` in PATH, `BW_SESSION` env var set (`export BW_SESSION=$(bw unlock --raw)`)

**Item naming convention:** One login item per auth key role per device:
```
YubiHSM2 HSM-1 admin
YubiHSM2 HSM-1 signer
YubiHSM2 HSM-2 admin
YubiHSM2 HSM-2 signer
YubiHSM2 HSM-3 admin
YubiHSM2 HSM-3 signer
```

**Retrieval:** Password is stored in `login.password`:
```bash
bw get item "YubiHSM2 HSM-1 admin" | jq -r '.login.password'
```

**Generation:** Use `bw generate` with strong defaults:
```bash
bw generate -p --length 32 --uppercase --lowercase --number --special
```

**Provisioning scripts** (`scripts/common.sh`) handle this automatically — `prompt_password` checks Bitwarden first via item name resolution, falls back to interactive prompt if `BW_SESSION` is not set or item is not found.

**Creating items:** Run `scripts/00-generate-passwords.sh` to generate 6 passwords and store them in Bitwarden as separate login items. Requires `BW_SESSION`.

### Pre-Flight Checks (MANDATORY)

Run these before EVERY workflow. Do not skip them.

```bash
# 1. Binary exists
which yubihsm-shell

# 2. Device reachable — branch on transport
case "$YUBIHSM_CONNECTOR_URL" in
  http://*|https://*)
    # Connector daemon — HTTP probe (add --cacert path for https://)
    curl -sf "$YUBIHSM_CONNECTOR_URL/connector/status"
    # Must contain: status=OK
    ;;
  yhusb://*)
    # Direct USB — verify the device is enumerated
    if [ "$(uname -s)" = "Linux" ]; then
      lsusb -d 1050:0030
    else
      system_profiler SPUSBDataType | grep -A2 -i yubihsm
    fi
    ;;
esac

# 3. Authenticated session works (any transport)
yubihsm-shell --connector "$YUBIHSM_CONNECTOR_URL" \
  --authkey "$YUBIHSM_AUTH_KEY_ID" -p "$YUBIHSM_PASSWORD" \
  -a get-device-info
```

If any step fails, stop and report. Do not proceed with HSM commands.

### Risk Classification

| Level | Operations | Rule |
|---|---|---|
| Read-only | list-objects, get-device-info, get-storage-info, get-logs, get-public-key, get-object-info | Execute without confirmation |
| Mutating | generate-*, put-*, sign-*, encrypt-*, decrypt-*, set-option, change-authkey | Describe what will happen, get one confirmation |
| Destructive | delete-*, reset-device | Warn irreversibility, get explicit confirmation |

**Factory reset requires double confirmation.**

**"I'm in a hurry" is not a reason to skip confirmations.** Destructive HSM operations are irreversible. Always confirm.

## Concepts

Object types, sessions, domains, capabilities, delegated capabilities, algorithms, audit log semantics — all in **`concepts-ref.md`**. Read it before designing access control or constructing capability strings.

## One-time host setup

SDK install (Linux/macOS), udev rules, connector daemon config, direct-USB enumeration check — all in **`setup-ref.md`**. Read it only when bootstrapping a new host. Routine operations do not need it.

## Workflows

### Initial Provisioning

1. Resolve credentials (user must confirm factory defaults if applicable)
2. Pre-flight checks
3. Open session with current auth key:
   ```bash
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a list-objects
   ```
4. **[Mutating]** Create audit auth key:
   ```bash
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a put-authentication-key -i 0 --label "audit" \
     --domains 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16 \
     -c get-log-entries --delegated get-log-entries \
     --new-password "<audit-password>"
   ```
5. **[Mutating]** Create operational auth key(s) — ask user for: label, domains, capabilities, delegated capabilities, password
6. Verify new auth keys work (list-objects with each)
7. **[Destructive]** Delete default auth key (ID 1):
   - Warn: "Deleting the default auth key is irreversible. If the new auth keys do not work, you will be locked out. The only recovery is factory reset, which destroys all objects."
   - Confirm before executing:
   ```bash
   yubihsm-shell --connector "$URL" --authkey "$NEW_KEY_ID" -p "$NEW_PASS" \
     -a delete-object -i 1 -t authentication-key
   ```
8. List objects to confirm final state

### Key Generation

1. Pre-flight, credentials
2. Ask user: key type, algorithm, label, domains, capabilities
3. For asymmetric keys: ask if `exportable-under-wrap` is needed (required for backup)
4. **[Mutating]** Execute:
   ```bash
   # Asymmetric
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a generate-asymmetric-key -i 0 --label "$LABEL" \
     --domains "$DOMAINS" -c "$CAPABILITIES" -A "$ALGORITHM"

   # Symmetric (firmware 2.3.1+)
   yubihsm-shell ... -a generate-symmetric-key ...

   # HMAC
   yubihsm-shell ... -a generate-hmac-key ...

   # Wrap key
   yubihsm-shell ... -a generate-wrap-key ... --delegated "$DELEGATED"
   ```
5. Show object info to confirm:
   ```bash
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a get-object-info -i "$OBJ_ID" -t "$OBJ_TYPE"
   ```

### Signing

1. Pre-flight, credentials
2. Get object info to determine key type/algorithm
3. **[Mutating]** Sign:
   ```bash
   # ECDSA
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a sign-ecdsa -i "$OBJ_ID" -A ecdsa-sha256 --in "$DATA_FILE" --out "$SIG_FILE"

   # EdDSA
   yubihsm-shell ... -a sign-eddsa -i "$OBJ_ID" --in "$DATA_FILE" --out "$SIG_FILE"

   # RSA PKCS#1 v1.5
   yubihsm-shell ... -a sign-pkcs1v15 -i "$OBJ_ID" -A rsa-pkcs1-sha256 --in "$DATA_FILE" --out "$SIG_FILE"

   # RSA-PSS
   yubihsm-shell ... -a sign-pss -i "$OBJ_ID" -A rsa-pss-sha256 --in "$DATA_FILE" --out "$SIG_FILE"

   # HMAC
   yubihsm-shell ... -a sign-hmac -i "$OBJ_ID" --in "$DATA_FILE" --out "$SIG_FILE"
   ```
4. Extract public key for verification:
   ```bash
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a get-public-key -i "$OBJ_ID" --out "$PUBKEY_FILE"
   ```
5. Provide OpenSSL verification command:
   ```bash
   openssl dgst -sha256 -verify "$PUBKEY_FILE" -signature "$SIG_FILE" "$DATA_FILE"
   ```

### Encryption/Decryption

```bash
# RSA-OAEP decrypt
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a decrypt-oaep -i "$OBJ_ID" -A rsa-oaep-sha256 --in "$ENC_FILE" --out "$DEC_FILE"

# RSA-PKCS1v1.5 decrypt
yubihsm-shell ... -a decrypt-pkcs1v15 -i "$OBJ_ID" --in "$ENC_FILE" --out "$DEC_FILE"

# AES-CBC encrypt (firmware 2.3.1+)
yubihsm-shell ... -a encrypt-aes-cbc -i "$OBJ_ID" --iv "$IV_HEX" --in "$PLAIN_FILE" --out "$ENC_FILE"

# AES-CBC decrypt
yubihsm-shell ... -a decrypt-aes-cbc -i "$OBJ_ID" --iv "$IV_HEX" --in "$ENC_FILE" --out "$DEC_FILE"

# AES-ECB encrypt/decrypt
yubihsm-shell ... -a encrypt-aes-ecb / decrypt-aes-ecb ...
```

### Backup & Restore

**Backup:**

1. Pre-flight, credentials
2. Generate random wrap key material and import to source HSM:
   ```bash
   # Generate 32 bytes for AES-256
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a get-pseudo-random --count 32 --out wrap_key.bin --outformat binary
   ```
3. **[Mutating]** Put wrap key on source — domains must cover ALL domains of objects to back up, delegated capabilities must be a superset of ALL objects' capabilities:
   ```bash
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a put-wrap-key -i 0 --label "backup-wrap" \
     --domains 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16 \
     -c export-wrapped,import-wrapped \
     --delegated "$ALL_NEEDED_CAPS" \
     -A aes256-ccm-wrap --in wrap_key.bin --informat binary
   ```
   Read `capabilities-ref.md` to construct the correct delegated capabilities string.
4. List all objects and check each has `exportable-under-wrap`:
   ```bash
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a list-objects
   # Then for each object:
   yubihsm-shell ... -a get-object-info -i "$OBJ_ID" -t "$OBJ_TYPE"
   ```
   Flag any objects missing `exportable-under-wrap` — these cannot be backed up.
5. Export each eligible object (action is `get-wrapped`, NOT `export-wrapped` — that is a capability name, not an action):
   ```bash
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a get-wrapped --wrap-id "$WRAP_ID" -i "$OBJ_ID" -t "$OBJ_TYPE" \
     --out "object_${OBJ_ID}.yhw"
   ```
6. Warn user: "The wrap key file (wrap_key.bin) contains sensitive material. Store it securely and delete from disk when done."

**Restore:**

1. Prompt for backup device connector URL
2. **[Mutating]** Import same wrap key to backup device:
   ```bash
   yubihsm-shell --connector "$BACKUP_URL" --authkey "$KEY_ID" -p "$PASS" \
     -a put-wrap-key -i "$WRAP_ID" --label "backup-wrap" \
     --domains 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16 \
     -c export-wrapped,import-wrapped \
     --delegated "$ALL_NEEDED_CAPS" \
     -A aes256-ccm-wrap --in wrap_key.bin --informat binary
   ```
3. Import each wrapped object (action is `put-wrapped`, NOT `import-wrapped`):
   ```bash
   yubihsm-shell --connector "$BACKUP_URL" --authkey "$KEY_ID" -p "$PASS" \
     -a put-wrapped --wrap-id "$WRAP_ID" --in "object_${OBJ_ID}.yhw"
   ```
4. Verify by listing objects on backup device and comparing against source

### Factory Reset

1. **Warn:** "Factory reset destroys ALL non-factory objects. This is irreversible. All keys, certificates, and data will be permanently lost."
2. Offer backup workflow if not already done
3. **First confirmation:** Ask user to confirm
4. **Second confirmation:** Ask user to type "RESET" to proceed
5. Execute:
   ```bash
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a reset
   ```
   Alternative: physical reset by holding touch sensor for 10+ seconds while inserting device.
6. Verify: open session with default auth key (ID 1, password "password")

### Access Control Design

1. Ask user: how many roles/applications, what operations each needs
2. Propose domain layout:
   - One domain per application/role is simplest
   - Shared domains for objects accessed by multiple roles
3. For each auth key, specify: domains, capabilities, delegated capabilities
4. On approval, create auth keys:
   ```bash
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a put-authentication-key -i 0 --label "$ROLE_LABEL" \
     --domains "$ROLE_DOMAINS" -c "$ROLE_CAPS" \
     --delegated "$ROLE_DELEGATED" --new-password "$ROLE_PASS"
   ```
5. Verify each auth key works

### Audit Log

```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a get-logs
```

Log store holds 62 entries in circular buffer. If force-audit is enabled and log is full, all operations except session open and log retrieval are blocked.

## Known Quirks (yubihsm-shell 2.7.0)

**`--out` appends, does not overwrite.** If the output file already exists, data is appended, producing a corrupt file. Always `rm -f` the output file before writing.

**Action names differ from capability names.** Examples: action `reset` vs capability `reset-device`; action `sign-pkcs1v15` vs capability `sign-pkcs`; action `get-public-key` vs capability (none — always allowed); action `get-logs` vs capability `get-log-entries`.

**`list-objects`, `get-object-info`, `get-public-key` require no capabilities.** These are always allowed for any authenticated session. Do not include them in capability strings — yubihsm-shell will reject them as invalid.

**`opaque-x509-certificate` requires DER format.** PEM certificates must be converted before import: `openssl x509 -in cert.pem -outform DER -out cert.der`

## Error Handling

| Code | Name | Cause | Recovery |
|---|---|---|---|
| 0x04 | AUTHENTICATION_FAILED | Wrong auth key ID or password | Verify credentials, check key exists |
| 0x05 | SESSIONS_FULL | 16 sessions open | Wait 30s for timeout or restart connector |
| 0x07 | STORAGE_FAILED | 256 objects / 126 KB limit | Delete unused objects |
| 0x09 | INSUFFICIENT_PERMISSIONS | Missing capability or domain | Check caps/domains on both auth key and target — read `capabilities-ref.md` |
| 0x0a | LOG_FULL | Log full + force-audit on | Retrieve log entries, then set-log-index |
| 0x0b | OBJECT_NOT_FOUND | Wrong ID/type or domain mismatch | List objects to verify, check domains |
| 0x11 | OBJECT_EXISTS | (Type, ID) already taken | Use different ID or delete existing first |

## Reference Files

- **`concepts-ref.md`** — objects, sessions, domains, capabilities, delegated capabilities, algorithms, audit log. Read before designing access control.
- **`setup-ref.md`** — one-time host setup: SDK install, udev rules, connector daemon config, USB enumeration check. Read only when bootstrapping a new host.
- **`command-reference.md`** — full syntax for every yubihsm-shell command. Read when you need exact flags for a command not covered above.
- **`capabilities-ref.md`** — complete capabilities, algorithms, and domains tables. Read when constructing capability strings.
