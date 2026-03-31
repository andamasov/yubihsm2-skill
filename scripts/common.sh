#!/usr/bin/env bash
# common.sh — Shared variables and helpers for YubiHSM 2 provisioning scripts
# Source this file from other scripts: source "$(dirname "$0")/common.sh"

set -euo pipefail

# --- Device Configuration ---
HSM1="https://10.217.32.191:12345"
HSM2="https://10.217.32.192:12345"
HSM3="https://10.217.72.234:12345"
ALL_HSMS=("$HSM1" "$HSM2" "$HSM3")
HSM_NAMES=("HSM-1" "HSM-2" "HSM-3")

# CA cert for HTTPS connectors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CACERT="$REPO_DIR/.claude/yubihsm-connector.crt"

# Certificate files
CERTS_DIR="$REPO_DIR/certs"

# Export directory for .yhw files
EXPORT_DIR="$REPO_DIR/exports"

# --- Object IDs ---
OBJ_ADMIN_KEY=0x0002
OBJ_SIGNER_KEY=0x0003
OBJ_WRAP_KEY=0x0010
OBJ_CA_KEY=0x0100
OBJ_CA_CERT=0x0101
OBJ_SIGNER_ASYM=0x0102
OBJ_SIGNER_CERT=0x0103
OBJ_CODESIGN=0x0200

# --- Capabilities ---
ADMIN_CAPS="put-asymmetric-key,generate-asymmetric-key,put-opaque,get-opaque,put-wrap-key,export-wrapped,import-wrapped,put-authentication-key,delete-authentication-key,delete-asymmetric-key,delete-opaque,delete-wrap-key,sign-pkcs,sign-ecdsa,get-pubkey,get-log-entries,get-pseudo-random,get-object-info,list-objects,reset-device"
ADMIN_DELEGATED="sign-pkcs,sign-ecdsa,get-opaque,exportable-under-wrap,export-wrapped,import-wrapped"

SIGNER_CAPS="sign-pkcs,sign-ecdsa,get-pubkey,get-opaque,get-object-info,list-objects"

WRAP_CAPS="export-wrapped,import-wrapped,exportable-under-wrap"
WRAP_DELEGATED="sign-pkcs,sign-ecdsa,get-opaque,exportable-under-wrap,export-wrapped,import-wrapped"

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
# Usage: hsm_default <connector_url> <action> [extra args...]
hsm_default() {
    local connector="$1" action="$2"
    shift 2
    hsm_cmd "$connector" 1 "password" "$action" "$@"
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

# Prompt for password with confirmation
# Usage: prompt_password "description"
# Sets PASSWORD variable
prompt_password() {
    local desc="$1"
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
