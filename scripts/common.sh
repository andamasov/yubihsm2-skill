#!/usr/bin/env bash
# common.sh — Shared variables and helpers for YubiHSM 2 provisioning scripts
# Source this file from other scripts: source "$(dirname "$0")/common.sh"

set -euo pipefail

# --- Device Configuration ---
# Edit these arrays to add/remove devices. First entry is always the primary.
# Provisioning scripts iterate ALL_HSMS. To skip a device, remove it from the arrays.
#
# Slots:
#   HSM-1 (primary)  = https://10.217.32.192:12345
#   HSM-2 (backup)   = https://10.217.32.191:12345 — provisioned 2026-06-13
#   HSM-3 (backup)   = https://10.217.72.234:12345
#   HSM-4 (reserved) = not yet assigned
#
ALL_HSMS=(
    "https://10.217.32.192:12345"   # HSM-1 primary
    "https://10.217.32.191:12345"   # HSM-2 backup
    "https://10.217.72.234:12345"   # HSM-3 backup
)
HSM_NAMES=(
    "HSM-1"
    "HSM-2"
    "HSM-3"
)

# Primary device (first in ALL_HSMS) — keys are generated here, others receive copies
PRIMARY_HSM="${ALL_HSMS[0]}"
PRIMARY_NAME="${HSM_NAMES[0]}"

# CA cert for HTTPS connectors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CACERT="$REPO_DIR/.claude/yubihsm-connector.crt"

# Certificate files
CERTS_DIR="$REPO_DIR/certs"

# Export directory for .yhw files
EXPORT_DIR="$REPO_DIR/exports"

# Attestation directory
ATTEST_DIR="$REPO_DIR/certs/attestation"

# --- Object IDs ---
OBJ_ADMIN_KEY=0x0002
OBJ_SIGNER_KEY=0x0003
OBJ_WRAP_KEY=0x0010
OBJ_TRANSPORT_WRAP=0x0011   # Temporary wrap key for device-to-device transfer
OBJ_CA_KEY=0x0100
OBJ_CA_CERT=0x0101
OBJ_SIGNER_ASYM=0x0102
OBJ_SIGNER_CERT=0x0103
OBJ_CODESIGN=0x0200

# --- Capabilities ---
ADMIN_CAPS="generate-asymmetric-key,put-asymmetric-key,delete-asymmetric-key,sign-pkcs,sign-pss,sign-ecdsa,sign-eddsa,decrypt-pkcs,decrypt-oaep,derive-ecdh,generate-symmetric-key,put-symmetric-key,delete-symmetric-key,encrypt-ecb,decrypt-ecb,encrypt-cbc,decrypt-cbc,generate-hmac-key,put-mac-key,delete-hmac-key,sign-hmac,verify-hmac,generate-wrap-key,put-wrap-key,delete-wrap-key,export-wrapped,import-wrapped,exportable-under-wrap,wrap-data,unwrap-data,put-public-wrap-key,delete-public-wrap-key,put-authentication-key,delete-authentication-key,change-authentication-key,sign-attestation-certificate,sign-ssh-certificate,get-template,put-template,delete-template,get-opaque,put-opaque,delete-opaque,create-otp-aead,decrypt-otp,generate-otp-aead-key,put-otp-aead-key,delete-otp-aead-key,randomize-otp-aead,rewrap-from-otp-aead-key,rewrap-to-otp-aead-key,get-log-entries,get-option,set-option,get-pseudo-random,reset-device"

# Delegated caps: all object-level capabilities
# (excludes device ops: get-log-entries, get-option, set-option, get-pseudo-random, reset-device)
DELEGATED_ALL="generate-asymmetric-key,put-asymmetric-key,delete-asymmetric-key,sign-pkcs,sign-pss,sign-ecdsa,sign-eddsa,decrypt-pkcs,decrypt-oaep,derive-ecdh,generate-symmetric-key,put-symmetric-key,delete-symmetric-key,encrypt-ecb,decrypt-ecb,encrypt-cbc,decrypt-cbc,generate-hmac-key,put-mac-key,delete-hmac-key,sign-hmac,verify-hmac,generate-wrap-key,put-wrap-key,delete-wrap-key,export-wrapped,import-wrapped,exportable-under-wrap,wrap-data,unwrap-data,put-public-wrap-key,delete-public-wrap-key,put-authentication-key,delete-authentication-key,change-authentication-key,sign-attestation-certificate,sign-ssh-certificate,get-template,put-template,delete-template,get-opaque,put-opaque,delete-opaque,create-otp-aead,decrypt-otp,generate-otp-aead-key,put-otp-aead-key,delete-otp-aead-key,randomize-otp-aead,rewrap-from-otp-aead-key,rewrap-to-otp-aead-key"
ADMIN_DELEGATED="$DELEGATED_ALL"

SIGNER_CAPS="sign-pkcs,sign-ecdsa,get-opaque"

WRAP_CAPS="export-wrapped,import-wrapped,exportable-under-wrap"
WRAP_DELEGATED="$DELEGATED_ALL"

# --- Bitwarden Integration ---
# Item names are derived from HSM_NAMES: "YubiHSM2 <name> admin" / "YubiHSM2 <name> signer"
# No need to maintain separate arrays — built dynamically from HSM_NAMES.

# --- FIPS activation default key password ---
# After FIPS activation, the default key password changes from "password" to this value.
# Used by phases 2 and 3 until the default key is deleted in phase 3.
FIPS_DEFAULT_PASS="password2"

# --- Helper Functions ---

# Run yubihsm-shell with common flags
# Usage: hsm_cmd <connector_url> <authkey_id> <password> <action> [extra args...]
hsm_cmd() {
    local connector="$1" authkey="$2" password="$3" action="$4"
    shift 4
    yubihsm-shell \
        --connector "$connector" \
        --cacert "$CACERT" \
        --authkey "$authkey" \
        -p "$password" \
        -a "$action" \
        "$@"
}

# Run yubihsm-shell with default auth key
# Tries FIPS_DEFAULT_PASS first, falls back to factory "password"
# Usage: hsm_default <connector_url> <action> [extra args...]
hsm_default() {
    local connector="$1" action="$2"
    shift 2
    if hsm_cmd "$connector" 1 "$FIPS_DEFAULT_PASS" "$action" "$@" 2>/dev/null; then
        return 0
    fi
    hsm_cmd "$connector" 1 "password" "$action" "$@"
}

# Change default auth key password via interactive REPL
# (no CLI action exists for this in yubihsm-shell 2.7.0)
# Usage: hsm_change_default_key <connector_url> <old_password> <new_password>
hsm_change_default_key() {
    local connector="$1" old_pass="$2" new_pass="$3"
    printf "connect\nsession open 1 %s\nchange authkey 0 1 %s\nsession close 0\nquit\n" \
        "$old_pass" "$new_pass" | \
        yubihsm-shell --connector "$connector" --cacert "$CACERT" 2>&1
}

# Check connector is reachable
# Usage: check_connector <connector_url>
check_connector() {
    local url="$1"
    local status
    status=$(curl -sf --cacert "$CACERT" "$url/connector/status" 2>/dev/null) || {
        echo "ERROR: Connector at $url is not reachable"
        return 1
    }
    if echo "$status" | grep -q "status=OK"; then
        echo "OK: $url"
    else
        echo "ERROR: Connector at $url returned unexpected status: $status"
        return 1
    fi
}

# Pre-flight checks
preflight() {
    echo "=== Pre-flight checks ==="
    if ! command -v yubihsm-shell &>/dev/null; then
        echo "ERROR: yubihsm-shell not found in PATH"
        exit 1
    fi
    echo "OK: yubihsm-shell found at $(which yubihsm-shell)"

    if [[ ! -f "$CACERT" ]]; then
        echo "ERROR: CA cert not found at $CACERT"
        exit 1
    fi
    echo "OK: CA cert found"
}

# Fetch password from Bitwarden by item name
# Usage: bw_get_password <item_name>
# Returns password on stdout, returns 1 if not available
bw_get_password() {
    local item_name="$1"

    if [[ -z "${BW_SESSION:-}" ]]; then
        return 1
    fi
    if ! command -v bw &>/dev/null || ! command -v jq &>/dev/null; then
        return 1
    fi

    local item_json
    item_json=$(bw get item "$item_name" 2>/dev/null) || return 1
    echo "$item_json" | jq -r '.login.password // empty' 2>/dev/null
}

# Resolve Bitwarden item name from description string
# Usage: _resolve_bw_item "HSM-1 admin" -> "YubiHSM2 HSM-1 admin"
_resolve_bw_item() {
    local desc="$1"
    local hsm_name="" role=""

    # Extract HSM name (HSM-1, HSM-2, HSM-3, HSM-4) from description
    if [[ "$desc" =~ (HSM-[0-9]+) ]]; then
        hsm_name="${BASH_REMATCH[1]}"
    fi

    case "$desc" in
        *admin*)  role="admin" ;;
        *signer*) role="signer" ;;
    esac

    if [[ -n "$hsm_name" && -n "$role" ]]; then
        echo "YubiHSM2 $hsm_name $role"
    fi
}

# Prompt for password — tries Bitwarden first, falls back to interactive
# Usage: prompt_password "HSM-1 admin"
# Sets PASSWORD variable
prompt_password() {
    local desc="$1"

    # Try Bitwarden
    local bw_item bw_pass
    bw_item=$(_resolve_bw_item "$desc")

    if [[ -n "$bw_item" ]]; then
        bw_pass=$(bw_get_password "$bw_item" 2>/dev/null) || true
        if [[ -n "$bw_pass" ]]; then
            echo "OK: Retrieved $desc password from Bitwarden"
            PASSWORD="$bw_pass"
            return
        fi
    fi

    # Fall back to interactive prompt
    local pass1 pass2
    while true; do
        read -rsp "Enter $desc password: " pass1
        echo
        read -rsp "Confirm $desc password: " pass2
        echo
        if [[ "$pass1" == "$pass2" ]]; then
            PASSWORD="$pass1"
            return
        fi
        echo "Passwords do not match. Try again."
    done
}

# Confirm destructive action
# Usage: confirm "description of what will happen"
confirm() {
    local msg="$1"
    echo
    echo "WARNING: $msg"
    read -rp "Type YES to confirm: " response
    if [[ "$response" != "YES" ]]; then
        echo "Aborted."
        exit 1
    fi
}

# Print section header
section() {
    echo
    echo "============================================"
    echo "  $1"
    echo "============================================"
    echo
}
