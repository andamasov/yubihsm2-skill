#!/usr/bin/env bash
# Phase 4: Import existing keys and certificates to HSM-1
source "$(dirname "$0")/common.sh"

preflight

section "Phase 4: Import Keys and Certs to HSM-1"

check_connector "$HSM1"

# Verify cert files exist
for f in vyos-uefi-ca.key vyos-uefi-ca.pem vyos-prod-2025-linux.key vyos-prod-2025-linux.pem; do
    if [[ ! -f "$CERTS_DIR/$f" ]]; then
        echo "ERROR: Required file not found: $CERTS_DIR/$f"
        exit 1
    fi
done
echo "OK: All certificate files found in $CERTS_DIR"

# Prompt for HSM-1 admin password
prompt_password "HSM-1 admin"
ADMIN_PASS="$PASSWORD"

# Verify admin key works
echo "Verifying admin key on HSM-1..."
hsm_cmd "$HSM1" 2 "$ADMIN_PASS" "list-objects"
echo "OK: Admin key verified"

# Import CA private key
echo
echo "--- Importing CA private key (ID $OBJ_CA_KEY) ---"
hsm_cmd "$HSM1" 2 "$ADMIN_PASS" "put-asymmetric-key" \
    -i "$OBJ_CA_KEY" \
    --label "vyos-uefi-ca" \
    --domains 1 \
    -c "sign-pkcs,exportable-under-wrap" \
    -A rsa4096 \
    --in "$CERTS_DIR/vyos-uefi-ca.key"
echo "OK: CA private key imported"

# Import CA certificate
echo
echo "--- Importing CA certificate (ID $OBJ_CA_CERT) ---"
hsm_cmd "$HSM1" 2 "$ADMIN_PASS" "put-opaque" \
    -i "$OBJ_CA_CERT" \
    --label "vyos-uefi-ca-cert" \
    --domains 1 \
    -c "get-opaque,exportable-under-wrap" \
    -A opaque-x509-certificate \
    --in "$CERTS_DIR/vyos-uefi-ca.pem"
echo "OK: CA certificate imported"

# Import signer private key
echo
echo "--- Importing signer private key (ID $OBJ_SIGNER_ASYM) ---"
hsm_cmd "$HSM1" 2 "$ADMIN_PASS" "put-asymmetric-key" \
    -i "$OBJ_SIGNER_ASYM" \
    --label "vyos-sb-signer-2025" \
    --domains 1 \
    -c "sign-pkcs,exportable-under-wrap" \
    -A rsa4096 \
    --in "$CERTS_DIR/vyos-prod-2025-linux.key"
echo "OK: Signer private key imported"

# Import signer certificate
echo
echo "--- Importing signer certificate (ID $OBJ_SIGNER_CERT) ---"
hsm_cmd "$HSM1" 2 "$ADMIN_PASS" "put-opaque" \
    -i "$OBJ_SIGNER_CERT" \
    --label "vyos-sb-signer-2025-cert" \
    --domains 1 \
    -c "get-opaque,exportable-under-wrap" \
    -A opaque-x509-certificate \
    --in "$CERTS_DIR/vyos-prod-2025-linux.pem"
echo "OK: Signer certificate imported"

# Verify
echo
echo "Objects on HSM-1 after import:"
hsm_cmd "$HSM1" 2 "$ADMIN_PASS" "list-objects"

section "Phase 4 Complete"
echo "All keys and certificates imported to HSM-1."
