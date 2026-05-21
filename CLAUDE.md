# yubishm2-skill

Claude Code skill and provisioning scripts for YubiHSM 2 operations.

## Repository Structure

```
skills/yubihsm2/          # Claude Code skill (symlink to ~/.claude/skills/yubihsm2)
  SKILL.md                # Main skill — execution model, workflows, Bitwarden integration
  command-reference.md    # Full yubihsm-shell command syntax
  capabilities-ref.md     # Capabilities, algorithms, domains tables
scripts/                  # Provisioning scripts
  common.sh               # Device config, object IDs, capabilities, helpers
  00-generate-passwords.sh # Generate and store passwords in Bitwarden
  01-factory-reset.sh      # Factory reset + FIPS activation + attestation cert extraction
  02-wrap-key.sh           # Generate and distribute shared wrap key
  03-auth-keys.sh          # Create admin/signer auth keys, delete default
  04-import-keys.sh        # Import CA key, CA cert, signer key, signer cert to primary
  05-generate-codesign.sh  # Generate ECDSA P-384 code signing key + attestation + CSR
  06-export.sh             # Export all objects from primary under wrap key
  07-import-backup.sh      # Import wrapped objects to backup devices
  08-verify.sh             # Verify all devices have correct objects and can sign
  09-cleanup.sh            # Secure delete private keys and export files
  provision-all.sh         # Master orchestrator (--from N to resume)
  add-device.sh            # Add a new device using transport wrap key (no raw key on disk)
certs/                    # Certificates and key material
  attestation/            # Attestation certs, Yubico CA chain, Sectigo package
.claude/                  # Connector CA cert, PKCS#11 config
```

## Device Configuration

Edit `ALL_HSMS` and `HSM_NAMES` arrays in `scripts/common.sh` to add/remove devices.
First entry is always the primary (keys generated here, others receive copies).

## Commands

```bash
# Full provisioning (phases 0-9)
./scripts/provision-all.sh

# Resume from specific phase
./scripts/provision-all.sh --from 3

# Add a new device later (uses transport wrap key, no raw key material on disk)
./scripts/add-device.sh <connector-url> <device-name>

# Syntax check all scripts
for f in scripts/*.sh; do bash -n "$f" && echo "$f: OK"; done
```

## Key Conventions

- All connectors use HTTPS with CA cert at `.claude/yubihsm-connector.crt`
- Passwords stored in Bitwarden: `YubiHSM2 <device-name> admin|signer`
- FIPS activation changes default key password from "password" to "password2"
- yubihsm-shell `--out` flag APPENDS — always `rm -f` before writing
- Certificates for `put-opaque` with `opaque-x509-certificate` must be DER format
- Capability name `put-mac-key` (not `put-hmac-key`) in yubihsm-shell 2.7.0
- Device ops (`get-log-entries`, `get-option`, etc.) cannot be used as delegated capabilities

## Jira

Epic: INFR-1034 (Infrastructure VyOS project at vyos.atlassian.net)
