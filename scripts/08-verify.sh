#!/usr/bin/env bash
# Phase 8: Verify all 3 devices have correct objects and can sign
source "$(dirname "$0")/common.sh"

preflight

section "Phase 8: Verify All Devices"

EXPECTED_OBJECTS=(
    "0x0002:authentication-key:admin"
    "0x0003:authentication-key:signer"
    "0x0010:wrap-key:shared-wrap"
    "0x0100:asymmetric-key:vyos-uefi-ca"
    "0x0101:opaque:vyos-uefi-ca-cert"
    "0x0102:asymmetric-key:vyos-sb-signer-2025"
    "0x0103:opaque:vyos-sb-signer-2025-cert"
    "0x0200:asymmetric-key:vyos-codesign"
)

ERRORS=0

for i in "${!ALL_HSMS[@]}"; do
    local_url="${ALL_HSMS[$i]}"
    local_name="${HSM_NAMES[$i]}"

    echo
    echo "=== Verifying $local_name ($local_url) ==="

    check_connector "$local_url"

    # Prompt for admin password to list all objects
    prompt_password "$local_name admin"
    ADMIN_PASS="$PASSWORD"

    echo "Object list:"
    object_list=$(hsm_cmd "$local_url" 2 "$ADMIN_PASS" "list-objects" 2>&1)
    echo "$object_list"

    # Check expected object count
    obj_count=$(echo "$object_list" | grep -c "^id:" || true)
    if [[ "$obj_count" -ne 8 ]]; then
        echo "ERROR: Expected 8 objects, found $obj_count on $local_name"
        ERRORS=$((ERRORS + 1))
    else
        echo "OK: 8 objects found"
    fi

    # Test signing with signer key
    echo
    echo "--- Testing ECDSA signature with signer key ---"
    prompt_password "$local_name signer"
    SIGNER_PASS="$PASSWORD"

    TEST_FILE="/tmp/yubihsm_verify_$$.txt"
    SIG_FILE="/tmp/yubihsm_verify_$$.sig"
    echo "test-verification-data" > "$TEST_FILE"

    if hsm_cmd "$local_url" 3 "$SIGNER_PASS" "sign-ecdsa" \
        -i "$OBJ_CODESIGN" \
        -A ecdsa-sha384 \
        --in "$TEST_FILE" \
        --out "$SIG_FILE" 2>/dev/null; then
        echo "OK: ECDSA signing works on $local_name"
    else
        echo "ERROR: ECDSA signing failed on $local_name"
        ERRORS=$((ERRORS + 1))
    fi

    # Test RSA signature
    RSA_SIG_FILE="/tmp/yubihsm_verify_rsa_$$.sig"
    if hsm_cmd "$local_url" 3 "$SIGNER_PASS" "sign-pkcs1v1_5" \
        -i "$OBJ_SIGNER_ASYM" \
        -A rsa-pkcs1-sha256 \
        --in "$TEST_FILE" \
        --out "$RSA_SIG_FILE" 2>/dev/null; then
        echo "OK: RSA PKCS#1 signing works on $local_name"
    else
        echo "ERROR: RSA signing failed on $local_name"
        ERRORS=$((ERRORS + 1))
    fi

    # Test opaque read
    if hsm_cmd "$local_url" 3 "$SIGNER_PASS" "get-opaque" \
        -i "$OBJ_CA_CERT" \
        --out /dev/null 2>/dev/null; then
        echo "OK: Opaque read (CA cert) works on $local_name"
    else
        echo "ERROR: Opaque read failed on $local_name"
        ERRORS=$((ERRORS + 1))
    fi

    rm -f "$TEST_FILE" "$SIG_FILE" "$RSA_SIG_FILE"
done

section "Phase 8 Complete"

if [[ "$ERRORS" -eq 0 ]]; then
    echo "All verifications passed on all 3 devices."
else
    echo "WARNING: $ERRORS error(s) detected. Review output above."
    exit 1
fi
