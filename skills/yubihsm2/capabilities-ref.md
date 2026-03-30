# YubiHSM 2 Capabilities, Algorithms & Domains Reference

## Capabilities

64-bit flags. Specify as comma-separated names: `sign-ecdsa,exportable-under-wrap`

### Asymmetric Key Operations

| Capability | Hex | Description |
|---|---|---|
| generate-asymmetric-key | 0x0000000000000010 | Generate asymmetric key on device |
| put-asymmetric-key | 0x0000000000000008 | Import asymmetric key |
| delete-asymmetric-key | 0x0000020000000000 | Delete asymmetric key |
| sign-pkcs | 0x0000000000000020 | RSA PKCS#1 v1.5 signing |
| sign-pss | 0x0000000000000040 | RSA-PSS signing |
| sign-ecdsa | 0x0000000000000080 | ECDSA signing |
| sign-eddsa | 0x0000000000000100 | EdDSA (Ed25519) signing |
| decrypt-pkcs | 0x0000000000000200 | RSA PKCS#1 v1.5 decryption |
| decrypt-oaep | 0x0000000000000400 | RSA-OAEP decryption |
| derive-ecdh | 0x0000000000000800 | ECDH key derivation |

### Symmetric Key Operations (firmware 2.3.1+)

| Capability | Hex | Description |
|---|---|---|
| generate-symmetric-key | 0x0001000000000000 | Generate symmetric key |
| put-symmetric-key | 0x0000800000000000 | Import symmetric key |
| delete-symmetric-key | 0x0002000000000000 | Delete symmetric key |
| encrypt-ecb | 0x0008000000000000 | AES-ECB encrypt |
| decrypt-ecb | 0x0004000000000000 | AES-ECB decrypt |
| encrypt-cbc | 0x0020000000000000 | AES-CBC encrypt |
| decrypt-cbc | 0x0010000000000000 | AES-CBC decrypt |

### HMAC Operations

| Capability | Hex | Description |
|---|---|---|
| generate-hmac-key | 0x0000000000200000 | Generate HMAC key |
| put-hmac-key | 0x0000000000100000 | Import HMAC key |
| delete-hmac-key | 0x0000080000000000 | Delete HMAC key |
| sign-hmac | 0x0000000000400000 | Compute HMAC |
| verify-hmac | 0x0000000000800000 | Verify HMAC |

### Wrap Key Operations

| Capability | Hex | Description |
|---|---|---|
| generate-wrap-key | 0x0000000000008000 | Generate wrap key |
| put-wrap-key | 0x0000000000004000 | Import wrap key |
| delete-wrap-key | 0x0000040000000000 | Delete wrap key |
| export-wrapped | 0x0000000000001000 | Export objects under wrap |
| import-wrapped | 0x0000000000002000 | Import wrapped objects |
| exportable-under-wrap | 0x0000000000010000 | Object can be exported via wrap key |
| wrap-data | 0x0000002000000000 | Wrap arbitrary data |
| unwrap-data | 0x0000004000000000 | Unwrap arbitrary data |

### Public Wrap Key Operations

| Capability | Hex | Description |
|---|---|---|
| put-public-wrap-key | 0x0040000000000000 | Import RSA public wrap key |
| delete-public-wrap-key | 0x0080000000000000 | Delete public wrap key |

### Authentication Key Operations

| Capability | Hex | Description |
|---|---|---|
| put-authentication-key | 0x0000000000000004 | Import authentication key |
| delete-authentication-key | 0x0000010000000000 | Delete authentication key |
| change-authentication-key | 0x0000400000000000 | Change auth key password |

### Certificate & Template Operations

| Capability | Hex | Description |
|---|---|---|
| sign-attestation-certificate | 0x0000000400000000 | Create attestation certificate |
| sign-ssh-certificate | 0x0000000002000000 | Sign SSH certificate |
| get-template | 0x0000000004000000 | Read template |
| put-template | 0x0000000008000000 | Store template |
| delete-template | 0x0000100000000000 | Delete template |

### Opaque Object Operations

| Capability | Hex | Description |
|---|---|---|
| get-opaque | 0x0000000000000001 | Read opaque object |
| put-opaque | 0x0000000000000002 | Store opaque object |
| delete-opaque | 0x0000008000000000 | Delete opaque object |

### OTP Operations

| Capability | Hex | Description |
|---|---|---|
| create-otp-aead | 0x0000000040000000 | Create OTP AEAD |
| decrypt-otp | 0x0000000020000000 | Decrypt OTP |
| generate-otp-aead-key | 0x0000001000000000 | Generate OTP AEAD key |
| put-otp-aead-key | 0x0000000800000000 | Import OTP AEAD key |
| delete-otp-aead-key | 0x0000200000000000 | Delete OTP AEAD key |
| randomize-otp-aead | 0x0000000080000000 | Re-randomize OTP AEAD |
| rewrap-from-otp-aead-key | 0x0000000100000000 | Rewrap OTP AEAD (source) |
| rewrap-to-otp-aead-key | 0x0000000200000000 | Rewrap OTP AEAD (target) |

### Device & Log Operations

| Capability | Hex | Description |
|---|---|---|
| get-log-entries | 0x0000000001000000 | Read audit log |
| get-option | 0x0000000000040000 | Read device options |
| set-option | 0x0000000000020000 | Set device options |
| get-pseudo-random | 0x0000000000080000 | Get random bytes |
| reset-device | 0x0000000010000000 | Factory reset |

## Delegated Capabilities Rules

**Auth key delegated capabilities:** Upper bound on capabilities assignable to objects created via this auth key. New object caps must be a subset of the auth key's delegated caps.

**Wrap key delegated capabilities:** Upper bound on capabilities of objects imported via this wrap key. Wrapped object caps must be a subset of the wrap key's delegated caps.

**Effective capabilities:** For any operation, effective caps = intersection of (auth key caps) AND (target object caps). Both must have the required capability.

### Common Delegated Capability Patterns

**Signing-only role:**
```
delegated: sign-ecdsa,sign-eddsa,sign-pkcs,sign-pss,exportable-under-wrap
```

**Full backup wrap key:**
```
delegated: sign-pkcs,sign-pss,sign-ecdsa,sign-eddsa,sign-hmac,verify-hmac,
  decrypt-pkcs,decrypt-oaep,derive-ecdh,encrypt-cbc,decrypt-cbc,encrypt-ecb,
  decrypt-ecb,wrap-data,unwrap-data,export-wrapped,import-wrapped,
  exportable-under-wrap,generate-asymmetric-key,generate-symmetric-key,
  generate-hmac-key,generate-wrap-key,put-asymmetric-key,put-symmetric-key,
  put-hmac-key,put-wrap-key,put-opaque,get-opaque,put-authentication-key,
  put-template,get-template,sign-ssh-certificate,sign-attestation-certificate,
  create-otp-aead,decrypt-otp,put-otp-aead-key,generate-otp-aead-key,
  randomize-otp-aead,rewrap-from-otp-aead-key,rewrap-to-otp-aead-key,
  change-authentication-key,get-log-entries,get-option,set-option,
  get-pseudo-random,delete-asymmetric-key,delete-authentication-key,
  delete-hmac-key,delete-opaque,delete-otp-aead-key,delete-template,
  delete-wrap-key,delete-symmetric-key,put-public-wrap-key,delete-public-wrap-key
```

**Admin auth key (can create anything):**
```
capabilities: generate-asymmetric-key,put-asymmetric-key,sign-ecdsa,
  export-wrapped,import-wrapped,put-wrap-key,generate-wrap-key,
  put-authentication-key,delete-asymmetric-key,delete-authentication-key,
  list-objects,get-object-info,get-log-entries,get-pseudo-random,get-pubkey
delegated: sign-ecdsa,sign-eddsa,sign-pkcs,sign-pss,exportable-under-wrap,
  decrypt-pkcs,decrypt-oaep,export-wrapped,import-wrapped
```

## Algorithms

### RSA Key Types

| Algorithm | Hex | Key Size |
|---|---|---|
| rsa2048 | 0x09 | 2048-bit |
| rsa3072 | 0x0a | 3072-bit |
| rsa4096 | 0x0b | 4096-bit |

### Elliptic Curve Key Types

| Algorithm | Hex | Curve |
|---|---|---|
| ecp224 | 0x0c | NIST P-224 |
| ecp256 | 0x0d | NIST P-256 |
| ecp384 | 0x0e | NIST P-384 |
| ecp521 | 0x2f | NIST P-521 |
| eck256 | 0x0f | secp256k1 |
| ecbp256 | 0x0f | Brainpool P-256 |
| ecbp384 | 0x10 | Brainpool P-384 |
| ecbp512 | 0x11 | Brainpool P-512 |
| ed25519 | 0x2e | Ed25519 |

### RSA Signature Algorithms

| Algorithm | Hex | Scheme |
|---|---|---|
| rsa-pkcs1-sha1 | 0x01 | PKCS#1 v1.5 + SHA-1 |
| rsa-pkcs1-sha256 | 0x02 | PKCS#1 v1.5 + SHA-256 |
| rsa-pkcs1-sha384 | 0x03 | PKCS#1 v1.5 + SHA-384 |
| rsa-pkcs1-sha512 | 0x04 | PKCS#1 v1.5 + SHA-512 |
| rsa-pss-sha1 | 0x05 | PSS + SHA-1 |
| rsa-pss-sha256 | 0x06 | PSS + SHA-256 |
| rsa-pss-sha384 | 0x07 | PSS + SHA-384 |
| rsa-pss-sha512 | 0x08 | PSS + SHA-512 |

### ECDSA Signature Algorithms

| Algorithm | Hex | Hash |
|---|---|---|
| ecdsa-sha1 | 0x17 | SHA-1 |
| ecdsa-sha256 | 0x2b | SHA-256 |
| ecdsa-sha384 | 0x2c | SHA-384 |
| ecdsa-sha512 | 0x2d | SHA-512 |

### RSA Decryption Algorithms

| Algorithm | Hex | Scheme |
|---|---|---|
| rsa-oaep-sha1 | 0x19 | OAEP + SHA-1 |
| rsa-oaep-sha256 | 0x1a | OAEP + SHA-256 |
| rsa-oaep-sha384 | 0x1b | OAEP + SHA-384 |
| rsa-oaep-sha512 | 0x1c | OAEP + SHA-512 |

### MGF1 Algorithms

| Algorithm | Hex |
|---|---|
| mgf1-sha1 | 0x20 |
| mgf1-sha256 | 0x21 |
| mgf1-sha384 | 0x22 |
| mgf1-sha512 | 0x23 |

### HMAC Algorithms

| Algorithm | Hex |
|---|---|
| hmac-sha1 | 0x13 |
| hmac-sha256 | 0x14 |
| hmac-sha384 | 0x15 |
| hmac-sha512 | 0x16 |

### AES Wrap Algorithms

| Algorithm | Hex | Key Size |
|---|---|---|
| aes128-ccm-wrap | 0x1d | 128-bit |
| aes192-ccm-wrap | 0x29 | 192-bit |
| aes256-ccm-wrap | 0x2a | 256-bit |

### AES Symmetric Algorithms (firmware 2.3.1+)

| Algorithm | Key Size |
|---|---|
| aes128 | 128-bit |
| aes192 | 192-bit |
| aes256 | 256-bit |

### Other Algorithms

| Algorithm | Hex | Purpose |
|---|---|---|
| opaque-data | 0x1e | Raw data storage |
| opaque-x509-certificate | 0x1f | X.509 certificate storage |
| template-ssh | 0x24 | SSH certificate template |
| aes128-yubico-otp | 0x25 | Yubico OTP (128-bit) |
| aes192-yubico-otp | 0x27 | Yubico OTP (192-bit) |
| aes256-yubico-otp | 0x28 | Yubico OTP (256-bit) |
| aes128-yubico-authentication | 0x26 | Yubico authentication |

## Domains

16 logical partitions. Objects and auth keys must share at least one domain for access.

| Domain | Hex Mask | Domain | Hex Mask |
|---|---|---|---|
| 1 | 0x0001 | 9 | 0x0100 |
| 2 | 0x0002 | 10 | 0x0200 |
| 3 | 0x0004 | 11 | 0x0400 |
| 4 | 0x0008 | 12 | 0x0800 |
| 5 | 0x0010 | 13 | 0x1000 |
| 6 | 0x0020 | 14 | 0x2000 |
| 7 | 0x0040 | 15 | 0x4000 |
| 8 | 0x0080 | 16 | 0x8000 |

Specify as comma-separated numbers: `--domains 1,2,3` or hex: `--domains 0x0007`

All domains: `1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16`

## Object Types

| Type | Shell Name | Hex |
|---|---|---|
| Opaque | opaque | 0x01 |
| Authentication Key | authentication-key | 0x02 |
| Asymmetric Key | asymmetric-key | 0x03 |
| Wrap Key | wrap-key | 0x04 |
| HMAC Key | hmac-key | 0x05 |
| Template | template | 0x06 |
| OTP AEAD Key | otp-aead-key | 0x07 |
| Symmetric Key | symmetric-key | 0x08 |
| Public Wrap Key | public-wrap-key | 0x09 |
