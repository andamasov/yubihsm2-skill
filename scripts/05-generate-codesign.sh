#!/usr/bin/env bash
# Phase 5: Generate code signing keypair on $PRIMARY_NAME and extract public key
source "$(dirname "$0")/common.sh"

preflight

section "Phase 5: Generate Code Signing Key on $PRIMARY_NAME"

check_connector "$PRIMARY_HSM"

# Prompt for HSM-1 admin password
prompt_password "$PRIMARY_NAME admin"
ADMIN_PASS="$PASSWORD"

# Generate ECDSA P-384 key
echo "Generating ECDSA P-384 code signing key (ID $OBJ_CODESIGN)..."
hsm_cmd "$PRIMARY_HSM" 2 "$ADMIN_PASS" "generate-asymmetric-key" \
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
hsm_cmd "$PRIMARY_HSM" 2 "$ADMIN_PASS" "get-public-key" \
    -i "$OBJ_CODESIGN" \
    --outformat PEM \
    --out "$PUBKEY_FILE"
echo "OK: Public key saved to $PUBKEY_FILE"

# Verify key info
echo
echo "Key info:"
hsm_cmd "$PRIMARY_HSM" 2 "$ADMIN_PASS" "get-object-info" \
    -i "$OBJ_CODESIGN" \
    -t asymmetric-key

# Generate attestation certificate
# This proves the key was generated on-device and chains to Yubico's root CA:
#   Yubico YubiHSM Root CA -> Device Sub-CA (intermediate) -> Key attestation cert
echo
echo "--- Generating attestation certificate ---"
ATTEST_FILE="$ATTEST_DIR/${PRIMARY_NAME}-codesign-attest.pem"
rm -f "$ATTEST_FILE"
if hsm_cmd "$PRIMARY_HSM" 2 "$ADMIN_PASS" "sign-attestation-certificate" \
    -i "$OBJ_CODESIGN" \
    --attestation-id 0 \
    --out "$ATTEST_FILE" 2>/dev/null; then
    echo "OK: Attestation cert saved to $ATTEST_FILE"
    openssl x509 -in "$ATTEST_FILE" -noout -subject -issuer

    # Verify attestation chain:
    #   Yubico Root CA -> Sub-CA -> Device intermediate -> Key attestation cert
    INTERMEDIATE="$ATTEST_DIR/${PRIMARY_NAME}-intermediate.pem"
    CHAIN="$ATTEST_DIR/chain.pem"
    if [[ -f "$INTERMEDIATE" && -f "$CHAIN" ]]; then
        echo
        echo "Verifying attestation chain..."
        cat "$INTERMEDIATE" "$CHAIN" > "$ATTEST_DIR/full-chain.pem"
        if openssl verify -CAfile "$ATTEST_DIR/full-chain.pem" "$ATTEST_FILE" 2>/dev/null; then
            echo "OK: Attestation chain verified"
            echo "    Key 0x0200 was generated on-device (not imported)"
        else
            echo "WARNING: Attestation chain verification failed"
        fi
    fi
else
    echo "WARNING: Could not generate attestation cert (attestation key may be missing)"
fi

# Generate CSR via PKCS#11
echo
echo "--- Generating CSR via PKCS#11 ---"
CSR_FILE="$ATTEST_DIR/vyos-codesign.csr"
PKCS11_CONF="$REPO_DIR/.claude/yubihsm_pkcs11.conf"
PKCS11_MODULE="/usr/local/lib/pkcs11/yubihsm_pkcs11.dylib"

if [[ -f "$PKCS11_CONF" && -f "$PKCS11_MODULE" ]]; then
    PIN="0002${ADMIN_PASS}"

    # Create temporary OpenSSL engine config
    OPENSSL_ENGINE_CONF=$(mktemp)
    cat > "$OPENSSL_ENGINE_CONF" << EOCNF
openssl_conf = openssl_init
[openssl_init]
engines = engine_section
[engine_section]
pkcs11 = pkcs11_section
[pkcs11_section]
engine_id = pkcs11
dynamic_path = /opt/homebrew/lib/engines-3/pkcs11.dylib
MODULE_PATH = $PKCS11_MODULE
PIN = $PIN
init = 0
[req]
distinguished_name = req_dn
[req_dn]
EOCNF

    export YUBIHSM_PKCS11_CONF="$PKCS11_CONF"
    rm -f "$CSR_FILE"
    if OPENSSL_CONF="$OPENSSL_ENGINE_CONF" openssl req -new \
        -engine pkcs11 \
        -keyform engine \
        -key "pkcs11:token=YubiHSM;id=%02%00;type=private" \
        -subj "/serialNumber=4578449/1.3.6.1.4.1.311.60.2.1.3=US/1.3.6.1.4.1.311.60.2.1.2=California/2.5.4.15=Private Organization/C=US/ST=California/L=Poway/O=VyOS Networks (VyOS Inc)/OU=IT/CN=VyOS Inc" \
        -sha384 \
        -out "$CSR_FILE" 2>/dev/null; then
        echo "OK: CSR saved to $CSR_FILE"
        openssl req -in "$CSR_FILE" -noout -subject
    else
        echo "WARNING: CSR generation failed"
    fi
    rm -f "$OPENSSL_ENGINE_CONF"
else
    echo "SKIP: PKCS#11 not configured (need $PKCS11_CONF and $PKCS11_MODULE)"
    echo "Generate CSR manually:"
    echo "  openssl req -new -engine pkcs11 -keyform engine \\"
    echo "    -key \"pkcs11:token=YubiHSM;id=%02%00;type=private\" \\"
    echo "    -subj \"/CN=VyOS Inc\" -sha384 -out vyos-codesign.csr"
fi

# Build Sectigo attestation package
echo
echo "--- Building Sectigo attestation package ---"
SECTIGO_DIR="$ATTEST_DIR/sectigo-package"
mkdir -p "$SECTIGO_DIR"
INTERMEDIATE="$ATTEST_DIR/${PRIMARY_NAME}-intermediate.pem"
SUB_CA="$ATTEST_DIR/yubihsm2-sub-ca.pem"
ROOT_CA="$ATTEST_DIR/yubihsm2-root-ca.pem"

PACKAGE_OK=true
for f in "$ATTEST_FILE" "$INTERMEDIATE" "$SUB_CA" "$ROOT_CA" "$CSR_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo "WARNING: Missing $f"
        PACKAGE_OK=false
    fi
done

if [[ "$PACKAGE_OK" == "true" ]]; then
    # Copy files into package directory with Sectigo-expected names
    cp "$ATTEST_FILE" "$SECTIGO_DIR/attestation.pem"
    cp "$INTERMEDIATE" "$SECTIGO_DIR/preloaded.pem"
    cp "$SUB_CA" "$SECTIGO_DIR/yubihsm2-sub-ca.pem"
    cp "$ROOT_CA" "$SECTIGO_DIR/yubihsm2-root-ca.pem"
    cp "$CSR_FILE" "$SECTIGO_DIR/vyos-codesign.csr"

    # Create attestation zip and base64 encode (Sectigo format)
    (cd "$SECTIGO_DIR" && zip -q attestation.zip attestation.pem preloaded.pem yubihsm2-sub-ca.pem yubihsm2-root-ca.pem)
    base64 < "$SECTIGO_DIR/attestation.zip" > "$SECTIGO_DIR/attestation.b64"

    # Also create DER versions for SSL.com
    openssl x509 -in "$ATTEST_FILE" -outform DER -out "$SECTIGO_DIR/attestation.der"
    openssl x509 -in "$INTERMEDIATE" -outform DER -out "$SECTIGO_DIR/preloaded.der"

    echo "OK: Attestation package built at $SECTIGO_DIR/"
    echo
    echo "Package contents:"
    ls -la "$SECTIGO_DIR/"
    echo
    echo "For Sectigo: submit vyos-codesign.csr and attestation.b64"
    echo "For SSL.com: submit vyos-codesign.csr and attestation.der"
fi

section "Phase 5 Complete"
echo "Code signing key generated on $PRIMARY_NAME."
echo "Public key: $PUBKEY_FILE"
if [[ -f "$ATTEST_FILE" ]]; then
    echo "Attestation cert: $ATTEST_FILE"
fi
if [[ -f "$CSR_FILE" ]]; then
    echo "CSR: $CSR_FILE"
fi
if [[ -d "$SECTIGO_DIR" ]]; then
    echo "Attestation package: $SECTIGO_DIR/"
fi
