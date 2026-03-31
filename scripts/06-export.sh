#!/usr/bin/env bash
# Phase 6: Export all objects from HSM-1 under shared wrap key
source "$(dirname "$0")/common.sh"

preflight

section "Phase 6: Export All Objects from HSM-1"

check_connector "$HSM1"

# Prompt for HSM-1 admin password
prompt_password "HSM-1 admin"
ADMIN_PASS="$PASSWORD"

# Create export directory
mkdir -p "$EXPORT_DIR"

# Objects to export: (id, type, label)
declare -a EXPORT_OBJECTS=(
    "$OBJ_CA_KEY:asymmetric-key:vyos-uefi-ca"
    "$OBJ_CA_CERT:opaque:vyos-uefi-ca-cert"
    "$OBJ_SIGNER_ASYM:asymmetric-key:vyos-sb-signer-2025"
    "$OBJ_SIGNER_CERT:opaque:vyos-sb-signer-2025-cert"
    "$OBJ_CODESIGN:asymmetric-key:vyos-codesign"
)

for entry in "${EXPORT_OBJECTS[@]}"; do
    IFS=':' read -r obj_id obj_type obj_label <<< "$entry"
    out_file="$EXPORT_DIR/export_${obj_id}.yhw"

    echo "Exporting $obj_label ($obj_id, $obj_type) -> $out_file"
    hsm_cmd "$HSM1" 2 "$ADMIN_PASS" "get-wrapped" \
        --wrap-id "$OBJ_WRAP_KEY" \
        -i "$obj_id" \
        -t "$obj_type" \
        --out "$out_file"
    echo "OK: $obj_label exported"
done

echo
echo "Exported files:"
ls -la "$EXPORT_DIR/"

section "Phase 6 Complete"
echo "All objects exported to $EXPORT_DIR/"
echo "These files are encrypted under the shared wrap key."
