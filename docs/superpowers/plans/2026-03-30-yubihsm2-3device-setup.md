# YubiHSM 2 Three-Device Setup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision 3 YubiHSM 2 devices with VyOS Secureboot keys, certificates, and a code signing key, with full backup replication across all devices.

**Architecture:** Shell scripts per provisioning phase, sourcing a shared `common.sh` for device config, object IDs, capabilities, and helper functions. A master `provision-all.sh` runs phases 1-9 sequentially with pause-between-phases for operator review.

**Tech Stack:** Bash, yubihsm-shell CLI, OpenSSL, curl

---

### Task 1: Create common.sh — Shared Configuration

**Files:**
- Create: `scripts/common.sh`

- [ ] **Step 1: Write common.sh with device config, object IDs, capabilities, and helpers**

All device URLs, object IDs, capability strings, and helper functions (`hsm_cmd`, `hsm_default`, `check_connector`, `preflight`, `prompt_password`, `confirm`, `section`).

- [ ] **Step 2: Verify it sources cleanly**

Run: `bash -n scripts/common.sh && source scripts/common.sh && echo "OK: $HSM1 $HSM2 $HSM3"`

Expected: `OK: https://10.217.32.191:12345 https://10.217.32.192:12345 https://10.217.72.234:12345`

- [ ] **Step 3: Commit**

```bash
git add scripts/common.sh
git commit -m "feat: add common.sh with device config and helpers"
```

---

### Task 2: Create 01-factory-reset.sh

**Files:**
- Create: `scripts/01-factory-reset.sh`

- [ ] **Step 1: Write factory reset script**

Iterates all 3 devices, confirms destructive action, resets each, waits for restart, verifies default auth key works.

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/01-factory-reset.sh`

Expected: no output (clean parse)

- [ ] **Step 3: Commit**

```bash
git add scripts/01-factory-reset.sh
git commit -m "feat: add factory reset script (phase 1)"
```

---

### Task 3: Create 02-wrap-key.sh

**Files:**
- Create: `scripts/02-wrap-key.sh`

- [ ] **Step 1: Write wrap key generation and distribution script**

Generates 32-byte random key, imports to all 3 devices as wrap key 0x0010, securely deletes key material.

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/02-wrap-key.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/02-wrap-key.sh
git commit -m "feat: add shared wrap key distribution script (phase 2)"
```

---

### Task 4: Create 03-auth-keys.sh

**Files:**
- Create: `scripts/03-auth-keys.sh`

- [ ] **Step 1: Write auth key creation script**

For each device: prompts for admin + signer passwords, creates both auth keys, verifies them, confirms and deletes default auth key.

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/03-auth-keys.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/03-auth-keys.sh
git commit -m "feat: add auth key provisioning script (phase 3)"
```

---

### Task 5: Create 04-import-keys.sh

**Files:**
- Create: `scripts/04-import-keys.sh`

- [ ] **Step 1: Write key/cert import script**

Verifies cert files exist, prompts for HSM-1 admin password, imports CA key (0x0100), CA cert (0x0101), signer key (0x0102), signer cert (0x0103).

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/04-import-keys.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/04-import-keys.sh
git commit -m "feat: add key/cert import script (phase 4)"
```

---

### Task 6: Create 05-generate-codesign.sh

**Files:**
- Create: `scripts/05-generate-codesign.sh`

- [ ] **Step 1: Write code signing key generation script**

Generates ECDSA P-384 key (0x0200) on HSM-1, extracts public key, prints CSR instructions for PKCS#11.

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/05-generate-codesign.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/05-generate-codesign.sh
git commit -m "feat: add code signing key generation script (phase 5)"
```

---

### Task 7: Create 06-export.sh

**Files:**
- Create: `scripts/06-export.sh`

- [ ] **Step 1: Write export script**

Exports all 5 objects (0x0100-0x0103, 0x0200) under shared wrap key (0x0010) to `.yhw` files in `exports/` directory.

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/06-export.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/06-export.sh
git commit -m "feat: add wrapped export script (phase 6)"
```

---

### Task 8: Create 07-import-backup.sh

**Files:**
- Create: `scripts/07-import-backup.sh`

- [ ] **Step 1: Write backup import script**

Verifies export files exist, imports all 5 `.yhw` files to HSM-2 and HSM-3 using their admin keys.

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/07-import-backup.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/07-import-backup.sh
git commit -m "feat: add backup device import script (phase 7)"
```

---

### Task 9: Create 08-verify.sh

**Files:**
- Create: `scripts/08-verify.sh`

- [ ] **Step 1: Write verification script**

On each device: checks 8 objects present, tests ECDSA signing (code signing key), RSA signing (signer key), opaque read (CA cert). Reports errors.

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/08-verify.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/08-verify.sh
git commit -m "feat: add device verification script (phase 8)"
```

---

### Task 10: Create 09-cleanup.sh

**Files:**
- Create: `scripts/09-cleanup.sh`

- [ ] **Step 1: Write cleanup script**

Deletes export `.yhw` files, securely deletes private key PEM files (with shred or rm -P), preserves public certs.

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/09-cleanup.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/09-cleanup.sh
git commit -m "feat: add secure cleanup script (phase 9)"
```

---

### Task 11: Create provision-all.sh — Master Script

**Files:**
- Create: `scripts/provision-all.sh`

- [ ] **Step 1: Write master script**

Runs phases 1-9 in sequence. Supports `--from N` to resume from a specific phase. Pauses between phases for operator review.

- [ ] **Step 2: Syntax check**

Run: `bash -n scripts/provision-all.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/provision-all.sh
git commit -m "feat: add master provisioning script"
```

---

### Task 12: Syntax Validation of All Scripts

- [ ] **Step 1: Run bash -n on all scripts**

```bash
for f in scripts/*.sh; do
    echo "Checking $f..."
    bash -n "$f" && echo "  OK" || echo "  FAIL"
done
```

Expected: all OK

- [ ] **Step 2: Verify all scripts are executable**

```bash
ls -la scripts/*.sh | awk '{print $1, $NF}'
```

Expected: all have `-rwxr-xr-x` permissions

- [ ] **Step 3: Final commit with .gitignore update**

```bash
# Add exports/ to .gitignore
echo "exports/" >> .gitignore
echo "*.yhw" >> .gitignore
echo "*.sig" >> .gitignore

git add .gitignore scripts/ docs/superpowers/plans/2026-03-30-yubihsm2-3device-setup.md
git commit -m "feat: complete provisioning scripts with implementation plan"
```

---

### Task 13: Live Test — Run Phase-by-Phase

This task is manual — run with real devices.

- [ ] **Step 1: Run provision-all.sh**

```bash
cd /Users/syncer/GitHub/yubishm2-skill
./scripts/provision-all.sh
```

Follow prompts, enter passwords when asked, confirm destructive operations.

- [ ] **Step 2: Verify all 3 devices independently**

```bash
./scripts/08-verify.sh
```

Expected: all verifications pass, 0 errors.

- [ ] **Step 3: Commit any fixes discovered during live test**

```bash
git add -u
git commit -m "fix: adjustments from live provisioning test"
```
