# YubiHSM 2 Three-Device Setup — Design Spec

## Overview

Provision 3 YubiHSM 2 devices for VyOS Secureboot and code signing operations. HSM-1 is the primary (daily signing), HSM-2 is a hot backup, HSM-3 is a cold backup. All devices hold identical key material, replicated via a shared wrap key.

## Devices

| Device | Role | Connector URL |
|---|---|---|
| HSM-1 | Primary | https://10.217.32.191:12345 |
| HSM-2 | Hot backup | https://10.217.32.192:12345 |
| HSM-3 | Cold backup | https://10.217.72.234:12345 |

- Same CA cert for all connectors: `.claude/yubihsm-connector.crt`
- All connectors use HTTPS; `yubihsm-shell` requires `--cacert` flag
- Firmware: 2.2.0

## Objects Per Device

All objects in domain 1.

| ID | Type | Label | Algorithm | Capabilities | Notes |
|---|---|---|---|---|---|
| 0x0002 | authentication-key | admin | aes128-yubico-auth | see below | Different password per device |
| 0x0003 | authentication-key | signer | aes128-yubico-auth | see below | Different password per device |
| 0x0010 | wrap-key | shared-wrap | aes256-ccm-wrap | see below | Same key material on all 3 |
| 0x0100 | asymmetric-key | vyos-uefi-ca | rsa4096 | sign-pkcs, exportable-under-wrap | Secureboot CA signing key |
| 0x0101 | opaque | vyos-uefi-ca-cert | opaque-x509-certificate | get-opaque, exportable-under-wrap | CA certificate |
| 0x0102 | asymmetric-key | vyos-sb-signer-2025 | rsa4096 | sign-pkcs, exportable-under-wrap | Secureboot signer key |
| 0x0103 | opaque | vyos-sb-signer-2025-cert | opaque-x509-certificate | get-opaque, exportable-under-wrap | Signer certificate |
| 0x0200 | asymmetric-key | vyos-codesign | ecp384 | sign-ecdsa, exportable-under-wrap | Code signing key (ECDSA P-384) |

Default auth key (ID 0x0001) is deleted after admin key is verified.

## Auth Key Specifications

### Admin key (0x0002)

**Capabilities:**
```
put-asymmetric-key, generate-asymmetric-key, put-opaque, get-opaque,
put-wrap-key, export-wrapped, import-wrapped,
put-authentication-key, delete-authentication-key, delete-asymmetric-key,
delete-opaque, delete-wrap-key,
sign-pkcs, sign-ecdsa, get-pubkey,
get-log-entries, get-pseudo-random, get-object-info, list-objects,
reset-device
```

**Delegated capabilities:**
```
sign-pkcs, sign-ecdsa, get-opaque, exportable-under-wrap,
export-wrapped, import-wrapped
```

### Signer key (0x0003)

**Capabilities:**
```
sign-pkcs, sign-ecdsa, get-pubkey, get-opaque, get-object-info, list-objects
```

**Delegated capabilities:** none

### Wrap key (0x0010)

**Capabilities:**
```
export-wrapped, import-wrapped, exportable-under-wrap
```

**Delegated capabilities:**
```
sign-pkcs, sign-ecdsa, get-opaque, exportable-under-wrap,
export-wrapped, import-wrapped
```

## Existing Key Material

Files in `certs/` directory of the repo:

| File | Content |
|---|---|
| `vyos-uefi-ca.key` | CA private key, RSA 4096, PEM |
| `vyos-uefi-ca.pem` | CA certificate, self-signed, CN=VyOS Networks Secure Boot CA, valid 2025-2125 |
| `vyos-uefi-ca.der` | CA certificate in DER format |
| `vyos-prod-2025-linux.key` | Secureboot signer private key, RSA 4096, PEM |
| `vyos-prod-2025-linux.pem` | Signer certificate, CN=VyOS Networks Secure Boot Signer 2025 - linux, signed by CA, valid 2025-2035 |
| `vyos-uefi-ca.srl` | CA serial number file |

## Provisioning Sequence

### Phase 1 — Factory Reset

Factory reset all 3 devices to clean state. Verify default auth key (ID 1, password "password") works on each.

### Phase 2 — Generate and Distribute Shared Wrap Key

1. Generate 32 bytes of random key material on local machine:
   ```bash
   openssl rand 32 > /tmp/wrap_key.bin
   ```
2. Import to all 3 devices as wrap key 0x0010 using default auth key:
   ```bash
   yubihsm-shell --connector $HSM_URL --cacert $CACERT --authkey 1 -p password \
     -a put-wrap-key -i 0x0010 --label "shared-wrap" \
     --domains 1 \
     -c export-wrapped,import-wrapped,exportable-under-wrap \
     --delegated sign-pkcs,sign-ecdsa,get-opaque,exportable-under-wrap,export-wrapped,import-wrapped \
     -A aes256-ccm-wrap --in /tmp/wrap_key.bin --informat binary
   ```
   Repeat for all 3 devices.
3. Securely delete key material:
   ```bash
   shred -u /tmp/wrap_key.bin 2>/dev/null || rm -P /tmp/wrap_key.bin
   ```

### Phase 3 — Create Auth Keys and Delete Default

On each device individually:

1. Create admin auth key (0x0002) — prompt user for password:
   ```bash
   yubihsm-shell --connector $HSM_URL --cacert $CACERT --authkey 1 -p password \
     -a put-authentication-key -i 0x0002 --label "admin" \
     --domains 1 \
     -c put-asymmetric-key,generate-asymmetric-key,put-opaque,get-opaque,put-wrap-key,export-wrapped,import-wrapped,put-authentication-key,delete-authentication-key,delete-asymmetric-key,delete-opaque,delete-wrap-key,sign-pkcs,sign-ecdsa,get-pubkey,get-log-entries,get-pseudo-random,get-object-info,list-objects,reset-device \
     --delegated sign-pkcs,sign-ecdsa,get-opaque,exportable-under-wrap,export-wrapped,import-wrapped \
     --new-password "$ADMIN_PASSWORD"
   ```
2. Create signer auth key (0x0003) — prompt user for password:
   ```bash
   yubihsm-shell --connector $HSM_URL --cacert $CACERT --authkey 1 -p password \
     -a put-authentication-key -i 0x0003 --label "signer" \
     --domains 1 \
     -c sign-pkcs,sign-ecdsa,get-pubkey,get-opaque,get-object-info,list-objects \
     --delegated none \
     --new-password "$SIGNER_PASSWORD"
   ```
3. Verify admin key works:
   ```bash
   yubihsm-shell --connector $HSM_URL --cacert $CACERT --authkey 2 -p "$ADMIN_PASSWORD" \
     -a list-objects
   ```
4. Verify signer key works:
   ```bash
   yubihsm-shell --connector $HSM_URL --cacert $CACERT --authkey 3 -p "$SIGNER_PASSWORD" \
     -a list-objects
   ```
5. Delete default auth key (ID 0x0001) — **destructive, irreversible**:
   ```bash
   yubihsm-shell --connector $HSM_URL --cacert $CACERT --authkey 2 -p "$ADMIN_PASSWORD" \
     -a delete-object -i 1 -t authentication-key
   ```

### Phase 4 — Import Keys and Certs to HSM-1

Using admin auth key on HSM-1:

1. Import CA private key:
   ```bash
   yubihsm-shell --connector $HSM1 --cacert $CACERT --authkey 2 -p "$ADMIN_PASSWORD_HSM1" \
     -a put-asymmetric-key -i 0x0100 --label "vyos-uefi-ca" \
     --domains 1 -c sign-pkcs,exportable-under-wrap -A rsa4096 \
     --in certs/vyos-uefi-ca.key
   ```
2. Import CA certificate:
   ```bash
   yubihsm-shell --connector $HSM1 --cacert $CACERT --authkey 2 -p "$ADMIN_PASSWORD_HSM1" \
     -a put-opaque -i 0x0101 --label "vyos-uefi-ca-cert" \
     --domains 1 -c get-opaque,exportable-under-wrap -A opaque-x509-certificate \
     --in certs/vyos-uefi-ca.pem
   ```
3. Import signer private key:
   ```bash
   yubihsm-shell --connector $HSM1 --cacert $CACERT --authkey 2 -p "$ADMIN_PASSWORD_HSM1" \
     -a put-asymmetric-key -i 0x0102 --label "vyos-sb-signer-2025" \
     --domains 1 -c sign-pkcs,exportable-under-wrap -A rsa4096 \
     --in certs/vyos-prod-2025-linux.key
   ```
4. Import signer certificate:
   ```bash
   yubihsm-shell --connector $HSM1 --cacert $CACERT --authkey 2 -p "$ADMIN_PASSWORD_HSM1" \
     -a put-opaque -i 0x0103 --label "vyos-sb-signer-2025-cert" \
     --domains 1 -c get-opaque,exportable-under-wrap -A opaque-x509-certificate \
     --in certs/vyos-prod-2025-linux.pem
   ```

### Phase 5 — Generate Code Signing Key on HSM-1

1. Generate ECDSA P-384 key:
   ```bash
   yubihsm-shell --connector $HSM1 --cacert $CACERT --authkey 2 -p "$ADMIN_PASSWORD_HSM1" \
     -a generate-asymmetric-key -i 0x0200 --label "vyos-codesign" \
     --domains 1 -c sign-ecdsa,exportable-under-wrap -A ecp384
   ```
2. Extract public key:
   ```bash
   yubihsm-shell --connector $HSM1 --cacert $CACERT --authkey 2 -p "$ADMIN_PASSWORD_HSM1" \
     -a get-pubkey -i 0x0200 --outformat PEM --out vyos-codesign-pub.pem
   ```
3. Generate CSR. The private key is inside the HSM, so CSR generation requires PKCS#11 to sign the request:
   ```bash
   # Requires: yubihsm_pkcs11 module configured (yubihsm_pkcs11.conf pointing to connector)
   openssl req -new -engine pkcs11 \
     -keyform engine \
     -key "pkcs11:id=%02%00;type=private" \
     -subj "/CN=VyOS Networks Code Signing" \
     -out vyos-codesign.csr
   ```
   Prerequisites: `yubihsm_pkcs11.so` installed, `yubihsm_pkcs11.conf` configured with connector URL. The PKCS#11 key ID `%02%00` corresponds to object ID 0x0200. The CSR is then sent to a CA for signing, or signed with the secureboot CA.

### Phase 6 — Export All Objects from HSM-1

Using admin auth key on HSM-1, export each object under the shared wrap key (0x0010):

```bash
# CA key
yubihsm-shell --connector $HSM1 --cacert $CACERT --authkey 2 -p "$ADMIN_PASSWORD_HSM1" \
  -a get-wrapped --wrap-id 0x0010 -i 0x0100 -t asymmetric-key --out export_0x0100.yhw

# CA cert
yubihsm-shell ... -a get-wrapped --wrap-id 0x0010 -i 0x0101 -t opaque --out export_0x0101.yhw

# Signer key
yubihsm-shell ... -a get-wrapped --wrap-id 0x0010 -i 0x0102 -t asymmetric-key --out export_0x0102.yhw

# Signer cert
yubihsm-shell ... -a get-wrapped --wrap-id 0x0010 -i 0x0103 -t opaque --out export_0x0103.yhw

# Code signing key
yubihsm-shell ... -a get-wrapped --wrap-id 0x0010 -i 0x0200 -t asymmetric-key --out export_0x0200.yhw
```

### Phase 7 — Import Wrapped Objects to HSM-2 and HSM-3

For each device, import all 5 `.yhw` files:

```bash
yubihsm-shell --connector $HSM_URL --cacert $CACERT --authkey 2 -p "$ADMIN_PASSWORD" \
  -a put-wrapped --wrap-id 0x0010 --in export_0x0100.yhw

yubihsm-shell ... -a put-wrapped --wrap-id 0x0010 --in export_0x0101.yhw
yubihsm-shell ... -a put-wrapped --wrap-id 0x0010 --in export_0x0102.yhw
yubihsm-shell ... -a put-wrapped --wrap-id 0x0010 --in export_0x0103.yhw
yubihsm-shell ... -a put-wrapped --wrap-id 0x0010 --in export_0x0200.yhw
```

Repeat for HSM-2 and HSM-3.

### Phase 8 — Verify

On each device, list objects and confirm 8 objects present:
- 0x0002 authentication-key (admin)
- 0x0003 authentication-key (signer)
- 0x0010 wrap-key (shared-wrap)
- 0x0100 asymmetric-key (vyos-uefi-ca)
- 0x0101 opaque (vyos-uefi-ca-cert)
- 0x0102 asymmetric-key (vyos-sb-signer-2025)
- 0x0103 opaque (vyos-sb-signer-2025-cert)
- 0x0200 asymmetric-key (vyos-codesign)

Verify a test signature on HSM-2 and HSM-3 produces a valid result:
```bash
echo "test" > /tmp/test.txt
yubihsm-shell --connector $HSM_URL --cacert $CACERT --authkey 3 -p "$SIGNER_PASSWORD" \
  -a sign-ecdsa -i 0x0200 -A ecdsa-sha384 --in /tmp/test.txt --out /tmp/test.sig
```

### Phase 9 — Cleanup

1. Delete `.yhw` export files:
   ```bash
   rm -f export_0x*.yhw
   ```
2. Securely delete PEM private key files:
   ```bash
   shred -u certs/vyos-uefi-ca.key certs/vyos-prod-2025-linux.key 2>/dev/null || \
     rm -P certs/vyos-uefi-ca.key certs/vyos-prod-2025-linux.key
   ```
   Keep certificates (`.pem`, `.der`) — these are public.

## Security Considerations

- Wrap key material exists on disk only during Phase 2, deleted immediately after import to all 3 devices
- PEM private keys are deleted after import to HSM-1 and successful replication to HSM-2 and HSM-3
- Admin passwords are per-device — compromise of one device's admin key does not grant access to others
- Signer key has no management capabilities — cannot export, delete, or create objects
- Factory reset requires `reset-device` capability, only on admin key
- The `.yhw` files are encrypted under the shared wrap key; without the wrap key (which exists only inside the HSMs), they are useless
