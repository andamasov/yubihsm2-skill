#!/usr/bin/env bash
# Phase 9: Secure cleanup of sensitive files
source "$(dirname "$0")/common.sh"

section "Phase 9: Cleanup"

# Delete export files
if [[ -d "$EXPORT_DIR" ]]; then
    echo "Deleting export .yhw files..."
    rm -f "$EXPORT_DIR"/export_*.yhw
    rmdir "$EXPORT_DIR" 2>/dev/null || true
    echo "OK: Export files deleted"
else
    echo "No export directory found (already cleaned)"
fi

# Securely delete private key files
PRIVATE_KEYS=(
    "$CERTS_DIR/vyos-uefi-ca.key"
    "$CERTS_DIR/vyos-prod-2025-linux.key"
)

echo
echo "The following private key files will be securely deleted:"
for f in "${PRIVATE_KEYS[@]}"; do
    if [[ -f "$f" ]]; then
        echo "  $f"
    fi
done

echo
echo "Public certificates (.pem, .der, .srl) will be kept."

confirm "Securely delete private key files from disk. This is irreversible."

for f in "${PRIVATE_KEYS[@]}"; do
    if [[ -f "$f" ]]; then
        echo "Deleting $f..."
        if command -v shred &>/dev/null; then
            shred -u "$f"
        elif [[ "$(uname)" == "Darwin" ]]; then
            rm -P "$f"
        else
            rm -f "$f"
        fi
        echo "OK: Deleted"
    else
        echo "SKIP: $f not found"
    fi
done

# Clean up public key if present
PUBKEY="$REPO_DIR/vyos-codesign-pub.pem"
if [[ -f "$PUBKEY" ]]; then
    echo
    echo "Code signing public key preserved at: $PUBKEY"
fi

echo
echo "Remaining files in certs/:"
ls -la "$CERTS_DIR/" 2>/dev/null || echo "  (empty or not found)"


section "Phase 9 Complete"
echo "Private keys securely deleted. Public certificates preserved."
echo
echo "Provisioning is complete. All 3 devices are ready for use."
