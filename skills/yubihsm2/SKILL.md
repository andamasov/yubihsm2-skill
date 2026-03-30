---
name: yubihsm2
description: Use when operating a YubiHSM 2 device — provisioning, key generation, signing, encryption, backup/restore, factory reset, access control design, or any yubihsm-shell / yubihsm-connector task
---

# YubiHSM 2 Operations

Operate YubiHSM 2 hardware security modules by executing `yubihsm-shell` commands via Bash. This skill executes commands directly — it does not just display them.

## Execution Model

### CLI Mode Only

All commands use one-shot invocations. Do NOT use interactive REPL mode.

```bash
yubihsm-shell \
  --connector "$YUBIHSM_CONNECTOR_URL" \
  --authkey "$YUBIHSM_AUTH_KEY_ID" \
  -p "$YUBIHSM_PASSWORD" \
  -a <action> [flags]
```

### Credential Resolution

1. Check env vars: `YUBIHSM_AUTH_KEY_ID`, `YUBIHSM_PASSWORD`, `YUBIHSM_CONNECTOR_URL`
2. If missing, prompt the user — do NOT assume defaults
3. `YUBIHSM_CONNECTOR_URL` defaults to `http://127.0.0.1:12345` only if user confirms

**Never assume auth key ID 1 / password "password" unless the user explicitly states they are using factory defaults.**

### Pre-Flight Checks (MANDATORY)

Run these before EVERY workflow. Do not skip them.

```bash
# 1. Binary exists
which yubihsm-shell

# 2. Connector reachable
curl -sf "$YUBIHSM_CONNECTOR_URL/connector/status"
# Must contain: status=OK
```

If either fails, stop and report. Do not proceed with HSM commands.

### Risk Classification

| Level | Operations | Rule |
|---|---|---|
| Read-only | list-objects, get-device-info, get-storage-info, get-log-entries, get-pubkey, get-object-info | Execute without confirmation |
| Mutating | generate-*, put-*, sign-*, encrypt-*, decrypt-*, set-option, change-authkey | Describe what will happen, get one confirmation |
| Destructive | delete-*, reset-device | Warn irreversibility, get explicit confirmation |

**Factory reset requires double confirmation.**

**"I'm in a hurry" is not a reason to skip confirmations.** Destructive HSM operations are irreversible. Always confirm.

## Concepts Primer

**Objects:** All persistent data in the HSM. 9 types: authentication-key, asymmetric-key, symmetric-key, wrap-key, hmac-key, opaque, template, otp-aead-key, public-wrap-key. Identified by (Type, ID) pair. Max 256 objects, 126 KB total. IDs 0x0000 and 0xFFFF are reserved; use 0 for auto-assign.

**Sessions:** All operations require an authenticated session. Opened with an authentication key. Max 16 concurrent, 30-second inactivity timeout. CLI mode (`-a`) handles session open/close automatically per invocation.

**Domains:** 16 logical partitions (1-16). Objects belong to one or more domains. An auth key can only access objects sharing at least one domain. Use domains to isolate applications or roles.

**Capabilities:** 64-bit flags controlling permitted operations. Both the auth key AND target object must possess the required capability. Example: to sign with ECDSA, the auth key needs `sign-ecdsa` and the asymmetric key also needs `sign-ecdsa`.

**Delegated Capabilities:** Only on auth keys and wrap keys. Upper bound on capabilities assignable to newly created or imported objects. If you create a key via an auth key, the new key's capabilities cannot exceed the auth key's delegated capabilities.

**Algorithms:** Specify crypto operations. See `capabilities-ref.md` for the full list. Common: `ecp256`, `ecp384`, `ed25519`, `rsa2048`, `rsa4096`, `aes256-ccm-wrap`, `hmac-sha256`.

**All object types are exportable under wrap** — including authentication keys. Auth keys CAN be backed up via wrap keys. Do not skip them during backup.

## Connector Setup

```bash
# Detect OS
uname -s  # Linux or Darwin

# Linux (Debian/Ubuntu)
sudo dpkg -i ./libyubihsm-usb1_*.deb ./libyubihsm-http1_*.deb \
  ./libyubihsm1_*.deb ./yubihsm-shell_*.deb ./yubihsm-connector_*.deb

# Linux (RHEL/CentOS)
sudo yum install ./yubihsm-shell-*.rpm ./yubihsm-connector-*.rpm

# macOS — install from SDK download
```

### udev Rules (Linux)

```bash
sudo tee /etc/udev/rules.d/99-yubihsm2.rules << 'EOF'
ACTION!="add|change", GOTO="yubihsm2_end"
SUBSYSTEM=="usb", ATTRS{idVendor}=="1050", ATTRS{idProduct}=="0030", OWNER="yubihsm-connector"
LABEL="yubihsm2_end"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger
```

### Connector Configuration

Config file: `/etc/yubihsm-connector.yaml`

```yaml
listen: localhost:12345    # Change for network access
serial: ""                 # Specify if multiple devices
syslog: false
```

### Start and Verify

```bash
# systemd
sudo systemctl enable --now yubihsm-connector

# or direct
yubihsm-connector -d

# verify
curl -sf http://127.0.0.1:12345/connector/status
```

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
   yubihsm-shell ... -a sign-pkcs1v1_5 -i "$OBJ_ID" -A rsa-pkcs1-sha256 --in "$DATA_FILE" --out "$SIG_FILE"

   # RSA-PSS
   yubihsm-shell ... -a sign-pss -i "$OBJ_ID" -A rsa-pss-sha256 --in "$DATA_FILE" --out "$SIG_FILE"

   # HMAC
   yubihsm-shell ... -a sign-hmac -i "$OBJ_ID" --in "$DATA_FILE" --out "$SIG_FILE"
   ```
4. Extract public key for verification:
   ```bash
   yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
     -a get-pubkey -i "$OBJ_ID" --out "$PUBKEY_FILE"
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
yubihsm-shell ... -a decrypt-pkcs1v1_5 -i "$OBJ_ID" --in "$ENC_FILE" --out "$DEC_FILE"

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
     -a reset-device
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
  -a get-log-entries
```

Log store holds 62 entries in circular buffer. If force-audit is enabled and log is full, all operations except session open and log retrieval are blocked.

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

- **`command-reference.md`** — full syntax for every yubihsm-shell command. Read when you need exact flags for a command not covered above.
- **`capabilities-ref.md`** — complete capabilities, algorithms, and domains tables. Read when constructing capability strings or planning access control.
