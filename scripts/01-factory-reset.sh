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

    # Try reset with default key first, then admin key from Bitwarden
    RESET_OK=false
    if hsm_default "$local_url" "reset" 2>/dev/null; then
        RESET_OK=true
    else
        echo "Default key failed, trying admin key from Bitwarden..."
        prompt_password "$local_name admin"
        if hsm_cmd "$local_url" 2 "$PASSWORD" "reset" 2>/dev/null; then
            RESET_OK=true
        else
            echo "ERROR: Failed to reset $local_name with both default and admin keys."
            echo "Try physical reset: insert device while holding touch sensor for 10+ seconds"
            exit 1
        fi
    fi

    if [[ "$RESET_OK" == "true" ]]; then
        echo "Device reset command sent."
    fi

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

    # FIPS activation sequence (per Sectigo requirements):
    #   1. Set fips-mode to 01 (may show as pending 03)
    #   2. Change default auth key password (activates FIPS → 01)
    # Must be done on factory-fresh device before any other changes.
    echo
    echo "--- FIPS Activation on $local_name ---"
    echo "Setting FIPS mode..."
    hsm_default "$local_url" "put-option" --opt-name "fips-mode" --opt-value "01" 2>/dev/null

    echo "Changing default auth key password to '$FIPS_DEFAULT_PASS' to activate FIPS..."
    change_result=$(hsm_change_default_key "$local_url" "password" "$FIPS_DEFAULT_PASS")
    if echo "$change_result" | grep -q "Changed Authentication key"; then
        echo "OK: Default auth key password changed to '$FIPS_DEFAULT_PASS'"
    else
        echo "ERROR: Failed to change default auth key password"
        echo "$change_result"
        exit 1
    fi

    # Verify FIPS mode active
    fips_status=$(hsm_default "$local_url" "get-option" --opt-name "fips-mode" 2>&1)
    if echo "$fips_status" | grep -q "01"; then
        echo "OK: FIPS mode active"
    else
        echo "WARNING: FIPS mode status: $fips_status"
    fi

    # Extract factory attestation intermediate cert (opaque ID 0)
    # This cert is pre-loaded at the factory and chains to Yubico's root CA.
    # It must be extracted now — it survives reset but may become inaccessible
    # after the default auth key is deleted if the new admin key lacks access.
    mkdir -p "$ATTEST_DIR"
    local_serial=$(hsm_default "$local_url" "get-device-info" 2>&1 | grep "Serial" | awk '{print $NF}')
    local_attest_file="$ATTEST_DIR/${local_name}-intermediate.pem"
    rm -f "$local_attest_file"
    echo "Extracting factory attestation cert from $local_name (serial $local_serial)..."
    if hsm_default "$local_url" "get-opaque" -i 0 --out "$local_attest_file.der" 2>/dev/null; then
        # Convert DER to PEM (get-opaque outputs raw DER)
        openssl x509 -in "$local_attest_file.der" -inform DER -out "$local_attest_file" -outform PEM
        rm -f "$local_attest_file.der"
        echo "OK: Saved to $local_attest_file"
        openssl x509 -in "$local_attest_file" -noout -subject -issuer 2>/dev/null
    else
        rm -f "$local_attest_file.der"
        echo "WARNING: Could not extract attestation cert from $local_name"
    fi
done

# Download Yubico YubiHSM root CA and Sub-CA
echo
echo "Downloading Yubico YubiHSM Root CA..."
curl -sf "https://developers.yubico.com/YubiHSM2/Concepts/yubihsm2-attest-ca-crt.pem" \
    -o "$ATTEST_DIR/yubihsm2-root-ca.pem"
if [[ -f "$ATTEST_DIR/yubihsm2-root-ca.pem" ]]; then
    echo "OK: Saved to $ATTEST_DIR/yubihsm2-root-ca.pem"
    openssl x509 -in "$ATTEST_DIR/yubihsm2-root-ca.pem" -noout -subject 2>/dev/null
else
    echo "WARNING: Could not download Yubico root CA"
fi

# Download Sub-CA using Authority Key Identifier from device intermediate cert
# All devices in a batch share the same Sub-CA
echo
echo "Downloading Yubico Sub-CA..."
SUB_CA_AKI=$(openssl x509 -in "$ATTEST_DIR/${HSM_NAMES[0]}-intermediate.pem" -noout -text 2>/dev/null \
    | grep -A1 "Authority Key Identifier" | tail -1 | tr -d ' :')
if [[ -n "$SUB_CA_AKI" ]]; then
    curl -sf "https://developers.yubico.com/YubiHSM2/Concepts/${SUB_CA_AKI}.pem" \
        -o "$ATTEST_DIR/yubihsm2-sub-ca.pem"
    if [[ -f "$ATTEST_DIR/yubihsm2-sub-ca.pem" ]]; then
        echo "OK: Saved to $ATTEST_DIR/yubihsm2-sub-ca.pem"
        openssl x509 -in "$ATTEST_DIR/yubihsm2-sub-ca.pem" -noout -subject 2>/dev/null
    else
        echo "WARNING: Could not download Sub-CA (AKI: $SUB_CA_AKI)"
    fi

    # Build full chain file: Sub-CA + Root CA
    cat "$ATTEST_DIR/yubihsm2-sub-ca.pem" "$ATTEST_DIR/yubihsm2-root-ca.pem" > "$ATTEST_DIR/chain.pem"
    echo "OK: Chain file built at $ATTEST_DIR/chain.pem"
else
    echo "WARNING: Could not extract Authority Key Identifier"
fi

section "Phase 1 Complete"
echo "All 3 devices reset to factory state with FIPS mode active."
echo "Default auth key password changed to '$FIPS_DEFAULT_PASS' on all devices."
echo "Factory attestation certs extracted to $ATTEST_DIR/"
