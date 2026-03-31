#!/usr/bin/env bash
# Phase 1: Factory reset all 3 YubiHSM 2 devices
source "$(dirname "$0")/common.sh"

preflight

section "Phase 1: Factory Reset"

echo "This will factory reset ALL 3 YubiHSM 2 devices."
echo "All non-factory objects will be permanently destroyed."
echo
echo "Devices:"
for i in "${!ALL_HSMS[@]}"; do
    echo "  ${HSM_NAMES[$i]}: ${ALL_HSMS[$i]}"
done

confirm "Factory reset all 3 devices. This is irreversible."

for i in "${!ALL_HSMS[@]}"; do
    local_url="${ALL_HSMS[$i]}"
    local_name="${HSM_NAMES[$i]}"

    echo
    echo "--- Resetting $local_name ($local_url) ---"

    check_connector "$local_url"

    hsm_default "$local_url" "reset-device" || {
        echo "ERROR: Failed to reset $local_name. It may already be in factory state."
        echo "Trying to verify default auth key..."
    }

    # Wait for device to come back after reset
    echo "Waiting for device to restart..."
    sleep 5

    # Verify default auth key works
    echo "Verifying default auth key on $local_name..."
    if hsm_default "$local_url" "list-objects"; then
        echo "OK: $local_name reset and default auth key working"
    else
        echo "ERROR: Cannot authenticate to $local_name with default key"
        echo "Try physical reset: insert device while holding touch sensor for 10+ seconds"
        exit 1
    fi
done

section "Phase 1 Complete"
echo "All 3 devices reset to factory state."
echo "Default auth key (ID 1, password 'password') verified on each."
