#!/usr/bin/env bash
# Phase 0: Generate HSM passwords and store in Bitwarden
source "$(dirname "$0")/common.sh"

section "Phase 0: Generate Passwords and Store in Bitwarden"

# Check prerequisites
if ! command -v bw &>/dev/null; then
    echo "ERROR: Bitwarden CLI (bw) not found in PATH"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq not found in PATH"
    exit 1
fi

if [[ -z "${BW_SESSION:-}" ]]; then
    echo "ERROR: BW_SESSION not set. Run: export BW_SESSION=\$(bw unlock --raw)"
    exit 1
fi

# Verify session is valid
if ! bw sync &>/dev/null; then
    echo "ERROR: BW_SESSION is invalid or expired. Run: export BW_SESSION=\$(bw unlock --raw)"
    exit 1
fi
echo "OK: Bitwarden session valid"

# Build item names from HSM_NAMES
ALL_BW_ITEMS=()
for name in "${HSM_NAMES[@]}"; do
    ALL_BW_ITEMS+=("YubiHSM2 $name admin" "YubiHSM2 $name signer")
done

# Check if any items already exist
EXISTING=0
for item_name in "${ALL_BW_ITEMS[@]}"; do
    if bw get item "$item_name" &>/dev/null; then
        echo "WARNING: Bitwarden item '$item_name' already exists"
        EXISTING=$((EXISTING + 1))
    fi
done

if [[ "$EXISTING" -gt 0 ]]; then
    confirm "Overwrite $EXISTING existing Bitwarden item(s). Old passwords will be lost."
    for item_name in "${ALL_BW_ITEMS[@]}"; do
        item_id=$(bw get item "$item_name" 2>/dev/null | jq -r '.id' 2>/dev/null) || true
        if [[ -n "$item_id" && "$item_id" != "null" ]]; then
            bw delete item "$item_id" &>/dev/null
            echo "Deleted existing item: $item_name"
        fi
    done
fi

PASSWORD_LENGTH=32

# Create a Bitwarden login item
# Usage: create_bw_item <item_name> <notes>
create_bw_item() {
    local item_name="$1" notes="$2"
    local password
    password=$(bw generate -p --length "$PASSWORD_LENGTH" --uppercase --lowercase --number --special)

    local item_json
    item_json=$(cat <<EOF
{
  "type": 1,
  "login": {"password": "$password"},
  "name": "$item_name",
  "notes": "$notes"
}
EOF
    )

    echo "$item_json" | bw encode | bw create item | jq -r '.name' > /dev/null
    echo "OK: Created '$item_name' (${#password} chars)"
}

# Generate admin + signer passwords for each device
for i in "${!ALL_HSMS[@]}"; do
    hsm_name="${HSM_NAMES[$i]}"
    hsm_url="${ALL_HSMS[$i]}"

    echo
    echo "--- $hsm_name ---"
    create_bw_item "YubiHSM2 $hsm_name admin" "$hsm_name ($hsm_url) — admin auth key (ID $OBJ_ADMIN_KEY)"
    create_bw_item "YubiHSM2 $hsm_name signer" "$hsm_name ($hsm_url) — signer auth key (ID $OBJ_SIGNER_KEY)"
done

# Sync to ensure items are available
bw sync &>/dev/null

section "Phase 0 Complete"
echo "${#ALL_HSMS[@]} devices x 2 roles = $((${#ALL_HSMS[@]} * 2)) passwords stored in Bitwarden:"
for name in "${HSM_NAMES[@]}"; do
    echo "  - YubiHSM2 $name admin"
    echo "  - YubiHSM2 $name signer"
done
