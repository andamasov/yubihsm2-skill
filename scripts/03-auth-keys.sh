#!/usr/bin/env bash
# Phase 3: Create admin + signer auth keys on each device, delete default
source "$(dirname "$0")/common.sh"

preflight

section "Phase 3: Create Auth Keys and Delete Default"

for i in "${!ALL_HSMS[@]}"; do
    local_url="${ALL_HSMS[$i]}"
    local_name="${HSM_NAMES[$i]}"

    echo
    echo "=== Provisioning auth keys on $local_name ($local_url) ==="

    check_connector "$local_url"

    # Prompt for admin password
    echo
    echo "--- Admin key for $local_name ---"
    prompt_password "$local_name admin"
    local_admin_pass="$PASSWORD"

    # Create admin auth key
    echo "Creating admin auth key (ID $OBJ_ADMIN_KEY)..."
    hsm_default "$local_url" "put-authentication-key" \
        -i "$OBJ_ADMIN_KEY" \
        --label "admin" \
        --domains 1 \
        -c "$ADMIN_CAPS" \
        --delegated "$ADMIN_DELEGATED" \
        --new-password "$local_admin_pass"
    echo "OK: Admin key created"

    # Prompt for signer password
    echo
    echo "--- Signer key for $local_name ---"
    prompt_password "$local_name signer"
    local_signer_pass="$PASSWORD"

    # Create signer auth key
    echo "Creating signer auth key (ID $OBJ_SIGNER_KEY)..."
    hsm_default "$local_url" "put-authentication-key" \
        -i "$OBJ_SIGNER_KEY" \
        --label "signer" \
        --domains 1 \
        -c "$SIGNER_CAPS" \
        --delegated "none" \
        --new-password "$local_signer_pass"
    echo "OK: Signer key created"

    # Verify admin key
    echo "Verifying admin key..."
    hsm_cmd "$local_url" 2 "$local_admin_pass" "list-objects"
    echo "OK: Admin key verified"

    # Verify signer key
    echo "Verifying signer key..."
    hsm_cmd "$local_url" 3 "$local_signer_pass" "list-objects"
    echo "OK: Signer key verified"

    # Delete default auth key
    confirm "Delete default auth key (ID 1) on $local_name. This is irreversible. If the new admin key doesn't work, the device is locked."

    echo "Deleting default auth key..."
    hsm_cmd "$local_url" 2 "$local_admin_pass" "delete-object" \
        -i 1 -t authentication-key
    echo "OK: Default auth key deleted on $local_name"

    # Final verification
    echo "Final object list on $local_name:"
    hsm_cmd "$local_url" 2 "$local_admin_pass" "list-objects"
    echo
done

section "Phase 3 Complete"
echo "All 3 devices have admin + signer auth keys."
echo "Default auth key deleted from all devices."
echo
echo "IMPORTANT: Record the admin and signer passwords for each device securely."
echo "There is no way to recover them."
