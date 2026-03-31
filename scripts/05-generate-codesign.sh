#!/usr/bin/env bash
# Phase 5: Generate code signing keypair on HSM-1 and extract public key
source "$(dirname "$0")/common.sh"

preflight

section "Phase 5: Generate Code Signing Key on HSM-1"

check_connector "$HSM1"

# Prompt for HSM-1 admin password
prompt_password "HSM-1 admin"
ADMIN_PASS="$PASSWORD"

# Generate ECDSA P-384 key
echo "Generating ECDSA P-384 code signing key (ID $OBJ_CODESIGN)..."
hsm_cmd "$HSM1" 2 "$ADMIN_PASS" "generate-asymmetric-key" \
    -i "$OBJ_CODESIGN" \
    --label "vyos-codesign" \
    --domains 1 \
    -c "sign-ecdsa,exportable-under-wrap" \
    -A ecp384
echo "OK: Code signing key generated"

# Extract public key
PUBKEY_FILE="$REPO_DIR/vyos-codesign-pub.pem"
echo
echo "Extracting public key..."
hsm_cmd "$HSM1" 2 "$ADMIN_PASS" "get-pubkey" \
    -i "$OBJ_CODESIGN" \
    --outformat PEM \
    --out "$PUBKEY_FILE"
echo "OK: Public key saved to $PUBKEY_FILE"

# Verify key info
echo
echo "Key info:"
hsm_cmd "$HSM1" 2 "$ADMIN_PASS" "get-object-info" \
    -i "$OBJ_CODESIGN" \
    -t asymmetric-key

section "Phase 5 Complete"
echo "Code signing key generated on HSM-1."
echo "Public key: $PUBKEY_FILE"
echo
echo "To generate a CSR, you need the PKCS#11 module configured."
echo "Example:"
echo "  openssl req -new -engine pkcs11 \\"
echo "    -keyform engine \\"
echo "    -key \"pkcs11:id=%02%00;type=private\" \\"
echo "    -subj \"/CN=VyOS Networks Code Signing\" \\"
echo "    -out vyos-codesign.csr"
echo
echo "Prerequisites: yubihsm_pkcs11.so installed, yubihsm_pkcs11.conf configured."
echo "PKCS#11 key ID %02%00 = object ID 0x0200."
