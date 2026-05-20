#!/usr/bin/env bash
# Phase 7: Import wrapped objects to HSM-2 and HSM-3
source "$(dirname "$0")/common.sh"

preflight

section "Phase 7: Import Wrapped Objects to HSM-2 and HSM-3"

# Verify export files exist
EXPORT_FILES=(
    "$EXPORT_DIR/export_${OBJ_CA_KEY}.yhw"
    "$EXPORT_DIR/export_${OBJ_CA_CERT}.yhw"
    "$EXPORT_DIR/export_${OBJ_SIGNER_ASYM}.yhw"
    "$EXPORT_DIR/export_${OBJ_SIGNER_CERT}.yhw"
    "$EXPORT_DIR/export_${OBJ_CODESIGN}.yhw"
)

for f in "${EXPORT_FILES[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: Export file not found: $f"
        echo "Run 06-export.sh first."
        exit 1
    fi
done
echo "OK: All export files found"

# Import to backup devices (all except HSM-1 primary)
BACKUP_HSMS=("${ALL_HSMS[@]:1}")
BACKUP_NAMES=("${HSM_NAMES[@]:1}")

for i in "${!BACKUP_HSMS[@]}"; do
    local_url="${BACKUP_HSMS[$i]}"
    local_name="${BACKUP_NAMES[$i]}"

    echo
    echo "=== Importing to $local_name ($local_url) ==="

    check_connector "$local_url"

    # Prompt for admin password
    prompt_password "$local_name admin"
    ADMIN_PASS="$PASSWORD"

    # Verify admin key works
    echo "Verifying admin key..."
    hsm_cmd "$local_url" 2 "$ADMIN_PASS" "list-objects"
    echo "OK: Admin key verified"

    # Import each wrapped object
    for f in "${EXPORT_FILES[@]}"; do
        fname="$(basename "$f")"
        echo "Importing $fname..."
        hsm_cmd "$local_url" 2 "$ADMIN_PASS" "put-wrapped" \
            --wrap-id "$OBJ_WRAP_KEY" \
            --in "$f"
        echo "OK: $fname imported"
    done

    echo
    echo "Objects on $local_name after import:"
    hsm_cmd "$local_url" 2 "$ADMIN_PASS" "list-objects"
done

section "Phase 7 Complete"
echo "All objects imported to HSM-2 and HSM-3."
