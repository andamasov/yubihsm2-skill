#!/usr/bin/env bash
# Add a new YubiHSM 2 device to the provisioned fleet.
# Transfers the shared wrap key and all objects from the primary device
# using a temporary transport wrap key (no raw key material on disk).
#
# Usage: ./scripts/add-device.sh <connector-url> <device-name>
#   e.g.: ./scripts/add-device.sh https://10.217.32.191:12345 HSM-2

source "$(dirname "$0")/common.sh"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <connector-url> <device-name>"
    echo "  e.g.: $0 https://10.217.32.191:12345 HSM-2"
    exit 1
fi

NEW_URL="$1"
NEW_NAME="$2"

preflight

section "Add Device: $NEW_NAME ($NEW_URL)"

# --- Step 1: Verify both devices reachable ---
echo "=== Checking connectors ==="
check_connector "$PRIMARY_HSM"
check_connector "$NEW_URL"

# --- Step 2: Verify new device is in factory state ---
echo
echo "=== Checking new device state ==="
if yubihsm-shell --connector "$NEW_URL" --cacert "$CACERT" --authkey 1 -p "password" \
    -a list-objects &>/dev/null; then
    echo "OK: $NEW_NAME has factory default auth key"
elif yubihsm-shell --connector "$NEW_URL" --cacert "$CACERT" --authkey 1 -p "$FIPS_DEFAULT_PASS" \
    -a list-objects &>/dev/null; then
    echo "OK: $NEW_NAME has FIPS-activated default auth key"
else
    echo "ERROR: Cannot authenticate to $NEW_NAME with default key."
    echo "Factory reset the device first."
    exit 1
fi

# --- Step 3: FIPS activation on new device ---
echo
echo "=== FIPS Activation on $NEW_NAME ==="
echo "Setting FIPS mode..."
hsm_default "$NEW_URL" "put-option" --opt-name "fips-mode" --opt-value "01" 2>/dev/null

# Check if already FIPS-activated (password already changed)
if yubihsm-shell --connector "$NEW_URL" --cacert "$CACERT" --authkey 1 -p "$FIPS_DEFAULT_PASS" \
    -a get-option --opt-name "fips-mode" &>/dev/null; then
    echo "OK: FIPS already activated"
else
    echo "Changing default auth key password to activate FIPS..."
    change_result=$(hsm_change_default_key "$NEW_URL" "password" "$FIPS_DEFAULT_PASS")
    if echo "$change_result" | grep -q "Changed Authentication key"; then
        echo "OK: FIPS activated"
    else
        echo "ERROR: Failed to activate FIPS"
        echo "$change_result"
        exit 1
    fi
fi

# Verify FIPS
fips_status=$(yubihsm-shell --connector "$NEW_URL" --cacert "$CACERT" --authkey 1 -p "$FIPS_DEFAULT_PASS" \
    -a get-option --opt-name "fips-mode" 2>&1)
echo "FIPS status: $fips_status"

# --- Step 4: Extract attestation cert from new device ---
echo
echo "=== Extracting attestation cert from $NEW_NAME ==="
mkdir -p "$ATTEST_DIR"
attest_file="$ATTEST_DIR/${NEW_NAME}-intermediate.pem"
rm -f "$attest_file"
if hsm_default "$NEW_URL" "get-opaque" -i 0 --out "${attest_file}.der" 2>/dev/null; then
    openssl x509 -in "${attest_file}.der" -inform DER -out "$attest_file" -outform PEM
    rm -f "${attest_file}.der"
    echo "OK: Saved to $attest_file"
    openssl x509 -in "$attest_file" -noout -subject -issuer
else
    rm -f "${attest_file}.der"
    echo "WARNING: Could not extract attestation cert"
fi

# --- Step 5: Create admin + signer auth keys on new device ---
echo
echo "=== Creating auth keys on $NEW_NAME ==="

prompt_password "$NEW_NAME admin"
new_admin_pass="$PASSWORD"

echo "Creating admin auth key (ID $OBJ_ADMIN_KEY)..."
yubihsm-shell --connector "$NEW_URL" --cacert "$CACERT" --authkey 1 -p "$FIPS_DEFAULT_PASS" \
    -a put-authentication-key -i "$OBJ_ADMIN_KEY" --label "admin" \
    --domains 1 \
    -c "$ADMIN_CAPS" \
    --delegated "$ADMIN_DELEGATED" \
    --new-password "$new_admin_pass"
echo "OK: Admin key created"

prompt_password "$NEW_NAME signer"
new_signer_pass="$PASSWORD"

echo "Creating signer auth key (ID $OBJ_SIGNER_KEY)..."
yubihsm-shell --connector "$NEW_URL" --cacert "$CACERT" --authkey 1 -p "$FIPS_DEFAULT_PASS" \
    -a put-authentication-key -i "$OBJ_SIGNER_KEY" --label "signer" \
    --domains 1 \
    -c "$SIGNER_CAPS" \
    --delegated "0" \
    --new-password "$new_signer_pass"
echo "OK: Signer key created"

# Verify new keys
echo "Verifying admin key..."
hsm_cmd "$NEW_URL" 2 "$new_admin_pass" "list-objects"
echo "Verifying signer key..."
hsm_cmd "$NEW_URL" 3 "$new_signer_pass" "list-objects"

# Delete default auth key
confirm "Delete default auth key (ID 1) on $NEW_NAME. Irreversible."
hsm_cmd "$NEW_URL" 2 "$new_admin_pass" "delete-object" -i 1 -t authentication-key
echo "OK: Default auth key deleted"

# --- Step 6: Transfer wrap key via temporary transport wrap key ---
echo
echo "=== Transferring shared wrap key to $NEW_NAME ==="

# Get primary admin password
prompt_password "$PRIMARY_NAME admin"
src_admin_pass="$PASSWORD"

# Generate temporary transport wrap key material
TRANSPORT_KEY_FILE="/tmp/transport_wrap_$$.bin"
openssl rand 32 > "$TRANSPORT_KEY_FILE"

echo "Importing transport wrap key to $PRIMARY_NAME..."
hsm_cmd "$PRIMARY_HSM" 2 "$src_admin_pass" "put-wrap-key" \
    -i "$OBJ_TRANSPORT_WRAP" \
    --label "transport-temp" \
    --domains 1 \
    -c "export-wrapped,import-wrapped" \
    --delegated "$DELEGATED_ALL" \
    -A aes256-ccm-wrap \
    --in "$TRANSPORT_KEY_FILE" \
    --informat binary
echo "OK: Transport key on $PRIMARY_NAME"

echo "Importing transport wrap key to $NEW_NAME..."
hsm_cmd "$NEW_URL" 2 "$new_admin_pass" "put-wrap-key" \
    -i "$OBJ_TRANSPORT_WRAP" \
    --label "transport-temp" \
    --domains 1 \
    -c "export-wrapped,import-wrapped" \
    --delegated "$DELEGATED_ALL" \
    -A aes256-ccm-wrap \
    --in "$TRANSPORT_KEY_FILE" \
    --informat binary
echo "OK: Transport key on $NEW_NAME"

# Securely delete transport key material
if command -v shred &>/dev/null; then
    shred -u "$TRANSPORT_KEY_FILE"
elif [[ "$(uname)" == "Darwin" ]]; then
    rm -P "$TRANSPORT_KEY_FILE"
else
    rm -f "$TRANSPORT_KEY_FILE"
fi
echo "OK: Transport key material deleted from disk"

# Export shared wrap key from primary under transport key
WRAPPED_WRAP_KEY="$EXPORT_DIR/transport_wrap_key.yhw"
mkdir -p "$EXPORT_DIR"
rm -f "$WRAPPED_WRAP_KEY"
echo "Exporting shared wrap key from $PRIMARY_NAME under transport key..."
hsm_cmd "$PRIMARY_HSM" 2 "$src_admin_pass" "get-wrapped" \
    --wrap-id "$OBJ_TRANSPORT_WRAP" \
    -i "$OBJ_WRAP_KEY" \
    -t wrap-key \
    --out "$WRAPPED_WRAP_KEY"
echo "OK: Shared wrap key exported"

# Import shared wrap key to new device
echo "Importing shared wrap key to $NEW_NAME..."
hsm_cmd "$NEW_URL" 2 "$new_admin_pass" "put-wrapped" \
    --wrap-id "$OBJ_TRANSPORT_WRAP" \
    --in "$WRAPPED_WRAP_KEY"
echo "OK: Shared wrap key imported to $NEW_NAME"

# Clean up transport wrap key from both devices
echo "Removing transport wrap key from both devices..."
hsm_cmd "$PRIMARY_HSM" 2 "$src_admin_pass" "delete-object" -i "$OBJ_TRANSPORT_WRAP" -t wrap-key
hsm_cmd "$NEW_URL" 2 "$new_admin_pass" "delete-object" -i "$OBJ_TRANSPORT_WRAP" -t wrap-key
rm -f "$WRAPPED_WRAP_KEY"
echo "OK: Transport wrap key removed"

# --- Step 7: Export all objects from primary and import to new device ---
echo
echo "=== Transferring objects to $NEW_NAME ==="

EXPORT_OBJECTS=(
    "$OBJ_CA_KEY:asymmetric-key:vyos-uefi-ca"
    "$OBJ_CA_CERT:opaque:vyos-uefi-ca-cert"
    "$OBJ_SIGNER_ASYM:asymmetric-key:vyos-sb-signer-2025"
    "$OBJ_SIGNER_CERT:opaque:vyos-sb-signer-2025-cert"
    "$OBJ_CODESIGN:asymmetric-key:vyos-codesign"
)

for entry in "${EXPORT_OBJECTS[@]}"; do
    IFS=':' read -r obj_id obj_type obj_label <<< "$entry"
    yhw_file="$EXPORT_DIR/transfer_${obj_id}.yhw"
    rm -f "$yhw_file"

    echo -n "  $obj_label ($obj_id): export..."
    hsm_cmd "$PRIMARY_HSM" 2 "$src_admin_pass" "get-wrapped" \
        --wrap-id "$OBJ_WRAP_KEY" \
        -i "$obj_id" -t "$obj_type" \
        --out "$yhw_file" 2>/dev/null

    echo -n " import..."
    hsm_cmd "$NEW_URL" 2 "$new_admin_pass" "put-wrapped" \
        --wrap-id "$OBJ_WRAP_KEY" \
        --in "$yhw_file" 2>/dev/null

    rm -f "$yhw_file"
    echo " OK"
done

# --- Step 8: Verify ---
echo
echo "=== Verification ==="
echo "Objects on $NEW_NAME:"
hsm_cmd "$NEW_URL" 2 "$new_admin_pass" "list-objects"

obj_count=$(hsm_cmd "$NEW_URL" 2 "$new_admin_pass" "list-objects" 2>&1 | grep -c "^id:" || true)
if [[ "$obj_count" -eq 8 ]]; then
    echo "OK: 8 objects present on $NEW_NAME"
else
    echo "WARNING: Expected 8 objects, found $obj_count"
fi

section "Add Device Complete"
echo "$NEW_NAME ($NEW_URL) is now part of the fleet."
echo "Objects replicated from $PRIMARY_NAME."
echo
echo "Remember to add $NEW_NAME to ALL_HSMS in scripts/common.sh"
