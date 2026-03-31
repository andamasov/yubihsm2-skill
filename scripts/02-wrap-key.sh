#!/usr/bin/env bash
# Phase 2: Generate shared wrap key and distribute to all 3 devices
source "$(dirname "$0")/common.sh"

preflight

section "Phase 2: Generate and Distribute Shared Wrap Key"

WRAP_KEY_FILE="/tmp/wrap_key_$$.bin"

# Generate 32 bytes of random key material
echo "Generating 32-byte AES-256 wrap key material..."
openssl rand 32 > "$WRAP_KEY_FILE"
echo "OK: Wrap key material generated at $WRAP_KEY_FILE"

# Import to all 3 devices
for i in "${!ALL_HSMS[@]}"; do
    local_url="${ALL_HSMS[$i]}"
    local_name="${HSM_NAMES[$i]}"

    echo
    echo "--- Importing wrap key to $local_name ($local_url) ---"

    check_connector "$local_url"

    hsm_default "$local_url" "put-wrap-key" \
        -i "$OBJ_WRAP_KEY" \
        --label "shared-wrap" \
        --domains 1 \
        -c "$WRAP_CAPS" \
        --delegated "$WRAP_DELEGATED" \
        -A aes256-ccm-wrap \
        --in "$WRAP_KEY_FILE" \
        --informat binary

    echo "OK: Wrap key imported to $local_name"
done

# Securely delete wrap key material
echo
echo "Securely deleting wrap key material from disk..."
if command -v shred &>/dev/null; then
    shred -u "$WRAP_KEY_FILE"
elif [[ "$(uname)" == "Darwin" ]]; then
    rm -P "$WRAP_KEY_FILE"
else
    rm -f "$WRAP_KEY_FILE"
fi
echo "OK: Wrap key material deleted"

section "Phase 2 Complete"
echo "Shared wrap key (ID $OBJ_WRAP_KEY) installed on all 3 devices."
echo "Wrap key material no longer exists on disk."
