# YubiHSM 2 Command Reference

Complete `yubihsm-shell` CLI command syntax. All commands use one-shot mode:

```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" -a <action> [flags]
```

Common flags across all commands:
- `--connector URL` — connector address (default: `http://127.0.0.1:12345`)
- `--authkey INT` — authentication key ID (default: 1)
- `-p, --password STRING` — authentication password
- `-i, --object-id SHORT` — object ID (use 0 for auto-assign)
- `-d, --domains STRING` — domain list: `1,2,3` or hex `0x0007`
- `-c, --capabilities STRING` — capability list: `sign-ecdsa,exportable-under-wrap` or hex
- `--delegated STRING` — delegated capabilities (same format as -c)
- `-A, --algorithm STRING` — algorithm name
- `-t, --object-type STRING` — object type name
- `--label STRING` — object label (max 40 bytes)
- `--in STRING` — input file (or `-` for stdin)
- `--out STRING` — output file (or stdout)
- `--informat ENUM` — input format: `base64`, `binary`, `PEM`, `hex`
- `--outformat ENUM` — output format: `base64`, `binary`, `PEM`, `hex`

## Session Commands

### open session
```bash
yubihsm-shell ... -a open-session
# Handled automatically in CLI mode. Rarely needed explicitly.
```

### open asymmetric session (firmware 2.3.1+)
```bash
yubihsm-shell --connector "$URL" -a open-session-asym --authkey 100 --in priv.key
```

## Device Commands

### get-device-info
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" -a get-device-info
```
Returns: firmware version, serial, supported algorithms, log capacity.

### get-storage-info
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" -a get-storage-info
```
Returns: total/free object slots and bytes.

### get-device-pubkey
```bash
yubihsm-shell --connector "$URL" -a get-device-pubkey --out device_pub.pem
```
No session required.

### blink-device
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" -a blink-device --duration 10
```

### reset-device
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" -a reset-device
```
Auth key must have `reset-device` capability. Destroys all non-factory objects.

## Key Generation

### generate-asymmetric-key
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a generate-asymmetric-key -i 0 --label "my-key" \
  --domains 1,2 -c sign-ecdsa,exportable-under-wrap -A ecp256
```
Algorithms: `rsa2048`, `rsa3072`, `rsa4096`, `ecp224`, `ecp256`, `ecp384`, `ecp521`, `eck256`, `ecbp256`, `ecbp384`, `ecbp512`, `ed25519`

### generate-symmetric-key (firmware 2.3.1+)
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a generate-symmetric-key -i 0 --label "my-aes" \
  --domains 1 -c encrypt-cbc,decrypt-cbc -A aes256
```
Algorithms: `aes128`, `aes192`, `aes256`

### generate-hmac-key
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a generate-hmac-key -i 0 --label "my-hmac" \
  --domains 1 -c sign-hmac,verify-hmac -A hmac-sha256
```
Algorithms: `hmac-sha1`, `hmac-sha256`, `hmac-sha384`, `hmac-sha512`

### generate-wrap-key
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a generate-wrap-key -i 0 --label "my-wrap" \
  --domains 1,2,3 -c export-wrapped,import-wrapped \
  --delegated sign-ecdsa,exportable-under-wrap -A aes256-ccm-wrap
```
Algorithms: `aes128-ccm-wrap`, `aes192-ccm-wrap`, `aes256-ccm-wrap`

### generate-otp-aead-key
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a generate-otp-aead-key -i 0 --label "otp-key" \
  --domains 1 -c decrypt-otp,create-otp-aead -A aes256-yubico-otp \
  --nonce-id 0x01020304
```

## Object Import (put)

### put-authentication-key
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a put-authentication-key -i 0 --label "admin" \
  --domains 1,2 -c generate-asymmetric-key,sign-ecdsa,list-objects \
  --delegated sign-ecdsa,exportable-under-wrap \
  --new-password "strongpassword"
```

### put-asymmetric-key
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a put-asymmetric-key -i 0 --label "imported-key" \
  --domains 1 -c sign-ecdsa -A ecp256 --in private.pem
```

### put-symmetric-key (firmware 2.3.1+)
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a put-symmetric-key -i 0 --label "imported-aes" \
  --domains 1 -c encrypt-cbc,decrypt-cbc -A aes256 --in key.bin --informat binary
```

### put-hmac-key
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a put-hmac-key -i 0 --label "imported-hmac" \
  --domains 1 -c sign-hmac,verify-hmac -A hmac-sha256 --in hmac_key.bin --informat binary
```

### put-wrap-key
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a put-wrap-key -i 0 --label "wrap" \
  --domains 1,2,3 -c export-wrapped,import-wrapped \
  --delegated sign-ecdsa,exportable-under-wrap \
  -A aes256-ccm-wrap --in wrap_key.bin --informat binary
```

### put-opaque
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a put-opaque -i 0 --label "ca-cert" \
  --domains 1 -c get-opaque -A opaque-x509-certificate --in cert.pem
```
Algorithms: `opaque-data`, `opaque-x509-certificate`

### put-template
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a put-template -i 0 --label "ssh-template" \
  --domains 1 -c sign-ssh-certificate -A template-ssh --in template.dat
```

## Object Management

### list-objects
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a list-objects
```
Optional filters: `-t asymmetric-key`, `--domains 1`, `-A ecp256`, `-c sign-ecdsa`

### get-object-info
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a get-object-info -i 0x0064 -t asymmetric-key
```

### delete-object
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a delete-object -i 0x0064 -t asymmetric-key
```
Valid types: `authentication-key`, `asymmetric-key`, `symmetric-key`, `wrap-key`, `hmac-key`, `opaque`, `template`, `otp-aead-key`, `public-wrap-key`

## Signing

### sign-ecdsa
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a sign-ecdsa -i 0x0064 -A ecdsa-sha256 --in data.txt --out sig.bin --outformat binary
```
Algorithms: `ecdsa-sha1`, `ecdsa-sha256`, `ecdsa-sha384`, `ecdsa-sha512`

### sign-eddsa
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a sign-eddsa -i 0x0064 --in data.txt --out sig.bin --outformat binary
```

### sign-pkcs1v1_5
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a sign-pkcs1v1_5 -i 0x0064 -A rsa-pkcs1-sha256 --in data.txt --out sig.bin
```
Algorithms: `rsa-pkcs1-sha1`, `rsa-pkcs1-sha256`, `rsa-pkcs1-sha384`, `rsa-pkcs1-sha512`

### sign-pss
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a sign-pss -i 0x0064 -A rsa-pss-sha256 --in data.txt --out sig.bin
```
Algorithms: `rsa-pss-sha1`, `rsa-pss-sha256`, `rsa-pss-sha384`, `rsa-pss-sha512`

### sign-hmac
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a sign-hmac -i 0x0064 --in data.txt --out hmac.bin
```

### verify-hmac
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a verify-hmac -i 0x0064 --in data.txt --hmac hmac.bin
```

### sign-ssh-certificate
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a sign-ssh-certificate -i 0x0064 --template-id 0x0010 --in request.dat --out cert.bin
```

### sign-attestation-certificate
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a sign-attestation-certificate -i 0x0064 --attestation-id 0 --out attest.pem
```
Attestation key at ID 0 is factory-installed.

## Decryption

### decrypt-pkcs1v1_5
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a decrypt-pkcs1v1_5 -i 0x0064 --in enc.bin --out dec.bin
```

### decrypt-oaep
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a decrypt-oaep -i 0x0064 -A rsa-oaep-sha256 --in enc.bin --out dec.bin
```
Algorithms: `rsa-oaep-sha1`, `rsa-oaep-sha256`, `rsa-oaep-sha384`, `rsa-oaep-sha512`

## Encryption (firmware 2.3.1+)

### encrypt-aes-cbc / decrypt-aes-cbc
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a encrypt-aes-cbc -i 0x0064 --iv 00000000000000000000000000000000 \
  --in plain.bin --out enc.bin

yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a decrypt-aes-cbc -i 0x0064 --iv 00000000000000000000000000000000 \
  --in enc.bin --out dec.bin
```

### encrypt-aes-ecb / decrypt-aes-ecb
```bash
yubihsm-shell ... -a encrypt-aes-ecb -i 0x0064 --in plain.bin --out enc.bin
yubihsm-shell ... -a decrypt-aes-ecb -i 0x0064 --in enc.bin --out dec.bin
```

## Key Derivation

### derive-ecdh
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a derive-ecdh -i 0x0064 --in peer_pubkey.pem --out shared_secret.bin
```

## Wrapping (Export/Import)

### get-wrapped (export object under wrap)
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a get-wrapped --wrap-id 0x0010 -i 0x0064 -t asymmetric-key \
  --out object.yhw
```

### put-wrapped (import wrapped object)
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a put-wrapped --wrap-id 0x0010 --in object.yhw
```

### get-rsa-wrapped (firmware 2.4+)
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a get-rsa-wrapped --wrap-id 0x0010 -i 0x0064 -t asymmetric-key \
  --aes aes256 --hash rsa-oaep-sha256 --mgf1 mgf1-sha256 --out object.enc
```

### put-rsa-wrapped (firmware 2.4+)
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a put-rsa-wrapped --wrap-id 0x0010 --in object.enc
```

### wrap-data / unwrap-data
```bash
# Wrap arbitrary data
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a wrap-data -i 0x0010 --in data.bin --out wrapped.bin

# Unwrap
yubihsm-shell ... -a unwrap-data -i 0x0010 --in wrapped.bin --out data.bin
```

## Public Key

### get-pubkey
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a get-pubkey -i 0x0064 --out pubkey.pem --outformat PEM
```

## Configuration

### change-authentication-key
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a change-authentication-key -i 0x0002 --new-password "newpassword"
```

### get-pseudo-random
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a get-pseudo-random --count 32 --out random.bin --outformat binary
```

### get-log-entries
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a get-log-entries
```

### set-log-index
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a set-log-index --log-index 42
```

### set-option
```bash
# Enable force-audit
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a set-option --opt force-audit --val 01

# Enable command audit for specific commands
yubihsm-shell ... -a set-option --opt command-audit --val "generate-asymmetric-key 01,sign-ecdsa 01"
```

### get-option
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a get-option --opt force-audit
```

## OTP Commands

### otp-aead-create
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a otp-aead-create -i 0x0064 \
  --otp-key 000102030405060708090a0b0c0d0e0f \
  --otp-id 010203040506 --out aead.bin
```

### otp-decrypt
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a otp-decrypt -i 0x0064 --otp "$OTP_STRING" --aead aead.bin
```

### otp-aead-randomize
```bash
yubihsm-shell ... -a otp-aead-randomize -i 0x0064 --in aead.bin --out new_aead.bin
```

### otp-aead-rewrap
```bash
yubihsm-shell ... -a otp-aead-rewrap --from-id 0x0064 --to-id 0x0065 --in aead.bin --out rewrapped.bin
```

## Utility

### echo (session)
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a echo --byte 0x3c --count 10
```

### plain-echo (no session)
```bash
yubihsm-shell --connector "$URL" -a plain-echo --byte 0x3c --count 10
```

### get-opaque
```bash
yubihsm-shell --connector "$URL" --authkey "$KEY_ID" -p "$PASS" \
  -a get-opaque -i 0x0064 --out data.bin
```
