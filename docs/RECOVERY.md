# YubiHSM 2 Recovery Procedures

Procedures for recovering individual HSMs after factory reset or loss. Public-safe — all secrets live in Bitwarden, not this repo.

## Backup hierarchy

```
transport_wrap.bin (32B AES-256 key material, in Bitwarden as secure note + attachment)
   │
   └─ wraps ─►  shared-wrap.yhw (encrypted blob, in Bitwarden as secure note + attachment)
                   │
                   └─ unwraps to ─►  shared-wrap (0x0010) on the target HSM
                                        │
                                        └─ unwraps ─►  per-object wrapped backups (.yhw files)
                                                       (asymmetric keys, certs, etc.)
```

To restore a freshly-reset HSM, you need **both** Bitwarden items below, in the order shown. Losing either makes recovery impossible from this backup path.

| Order | Bitwarden item | Contents |
|---|---|---|
| 1 | `YubiHSM2 transport-wrap key material (2026-05-21)` | Raw 32-byte AES-256 key (attachment: `transport_wrap.bin`). Reprompt-protected. |
| 2 | `YubiHSM2 shared-wrap key (wrapped, 2026-05-21)` | shared-wrap key, wrapped by transport-wrap (attachment: `shared-wrap.yhw`). Reprompt-protected. |
| 3 | Per-object `.yhw` backups | Wrapped by shared-wrap. Storage location TBD per object class (codesign, UEFI CA, sb-signer). |

## Restoring a freshly-reset HSM (e.g. HSM-2 after factory reset)

**Prerequisites:**
- Target HSM physically available (USB or via a connector daemon).
- Source-device admin auth (HSM-1 or HSM-3) — for sanity comparison once restored.
- Target-device admin auth — created via `scripts/00-generate-passwords.sh` flow against the *fresh* target before this procedure.
- Bitwarden unlocked.

**Steps:**

1. **Provision auth keys on the freshly-reset target.** Use the standard provisioning sequence (`scripts/01-factory-reset.sh` → `scripts/03-auth-keys.sh` if you ran factory reset via the script suite; otherwise create `admin` and `signer` auth keys manually from the factory default). Verify by listing objects — should see only the new admin/signer.

2. **Download both Bitwarden attachments** to a working directory:
   ```bash
   WORK=$(mktemp -d)
   ITEM1=$(bw list items --search "YubiHSM2 transport-wrap key material" | jq -r '.[0].id')
   ITEM2=$(bw list items --search "YubiHSM2 shared-wrap key (wrapped" | jq -r '.[0].id')
   ATT1=$(bw get item "$ITEM1" | jq -r '.attachments[0].id')
   ATT2=$(bw get item "$ITEM2" | jq -r '.attachments[0].id')
   bw get attachment "$ATT1" --itemid "$ITEM1" --output "$WORK/transport_wrap.bin"
   bw get attachment "$ATT2" --itemid "$ITEM2" --output "$WORK/shared-wrap.yhw"
   ```

3. **Verify integrity** against the SHA-256 fingerprints recorded in each Bitwarden item's notes. Mismatch = abort. Do not import an altered key.
   ```bash
   shasum -a 256 "$WORK/transport_wrap.bin" "$WORK/shared-wrap.yhw"
   ```

4. **Put `transport-wrap` (0x0011) on the target.** Use the admin auth key. The full delegated-capability string is in the Bitwarden note body — copy it verbatim.
   ```bash
   yubihsm-shell --connector <URL> --authkey <admin_id> -p <admin_pwd> \
     -a put-wrap-key -i 0x0011 --label transport-wrap \
     --domains 1 -c export-wrapped,import-wrapped \
     --delegated '<long delegated list from Bitwarden notes>' \
     -A aes256-ccm-wrap \
     --in "$WORK/transport_wrap.bin" --informat binary
   ```

5. **Import the wrapped shared-wrap blob** using transport-wrap. This re-materializes `shared-wrap` as object `0x0010` on the target.
   ```bash
   yubihsm-shell ... -a put-wrapped --wrap-id 0x0011 --in "$WORK/shared-wrap.yhw"
   yubihsm-shell ... -a get-object-info -i 0x0010 -t wrap-key   # verify
   ```

6. **Import each per-object wrapped backup** using shared-wrap. (Per-object `.yhw` files are stored separately; see `scripts/07-import-backup.sh` for the canonical batch procedure.)
   ```bash
   yubihsm-shell ... -a put-wrapped --wrap-id 0x0010 --in <object>.yhw
   ```

7. **Verify object set matches HSM-1/HSM-3.** Should be 8 objects (admin, signer, shared-wrap, vyos-uefi-ca + cert, vyos-sb-signer-2025 + cert, vyos-codesign), plus the new `transport-wrap` (0x0011) — 9 total — or delete transport-wrap if the target shouldn't keep it (see §"Whether to keep transport-wrap on the device").
   ```bash
   yubihsm-shell ... -a list-objects
   ```

8. **Shred the working directory.**
   ```bash
   rm -P "$WORK/transport_wrap.bin" "$WORK/shared-wrap.yhw"
   rmdir "$WORK"
   ```

9. **Test signing end-to-end** with a known piece of data on the restored device; verify the signature externally with the public key already known for that signer.

## Whether to keep `transport-wrap` (0x0011) on the device

After restore, you have a choice:

- **Keep it.** Useful if the device needs to act as a wrap source for further restores. Adds attack surface — anyone with admin auth + the on-device `transport-wrap` can re-export `shared-wrap`.
- **Delete it.** Cleaner threat model — fewer wrap keys at rest. Re-importable from Bitwarden if needed.

Current policy: keep `transport-wrap` on HSM-3 (the device that exported `shared-wrap`), since HSM-3 is the local device used for periodic backups and rewraps. Future HSM-2 should likely **delete** `transport-wrap` after restore — it's a backup destination, not a source.

## Re-generating the backup (rotating transport-wrap)

Recommended yearly, or whenever the operator who owns the Bitwarden secret changes.

1. Generate a new `transport_wrap.bin` via HSM hardware RNG.
2. Put it as a new wrap key (e.g. `0x0012 transport-wrap-2026Q4`) with the same delegated capabilities.
3. `get-wrapped` the existing shared-wrap under the new transport key → `shared-wrap-2026Q4.yhw`.
4. Create new Bitwarden items with the new material; attach files; verify round-trip.
5. Delete the old Bitwarden items (old transport-wrap + old wrapped blob).
6. Optional: delete the old `0x0011 transport-wrap` from the device once the new key is in Bitwarden and round-trip-verified.

## Audit log maintenance

Every operation appends one entry to the device's 62-entry circular audit log. If the log fills:

- With `force-audit` ON → all ops except `session-open` and `get-logs` are refused. **Device becomes unresponsive until the log is drained.** This is the failure mode that locked HSM-2.
- With `force-audit` OFF → entries silently overwrite (audit history lost).

**Drain procedure:**

```bash
yubihsm-shell ... --authkey <admin> -p <pwd> -a get-logs > "logs-$(date +%F).txt"
LASTIDX=$(awk '/^item:/ {print $2}' "logs-$(date +%F).txt" | sort -n | tail -1)
yubihsm-shell ... -a set-log-index --log-index "$LASTIDX"
yubihsm-shell ... -a get-device-info | grep "Log used"   # verify low number
```

Run this on every device on a schedule. Recommended: weekly cron for any device with `force-audit` OFF, daily cron for any device with `force-audit` ON.

A dedicated `audit` auth key with only the `get-log-entries` capability (no admin powers) is the right least-privilege approach — see the skill's "Initial Provisioning" workflow.
