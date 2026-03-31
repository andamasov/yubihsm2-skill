#!/usr/bin/env bash
# Master script: Run all provisioning phases in sequence
# Usage: ./provision-all.sh [--from PHASE]
#   --from PHASE  Start from a specific phase (1-9), skipping earlier phases

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
START_PHASE=1

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)
            START_PHASE="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--from PHASE]"
            echo "  --from PHASE  Start from phase 1-9 (default: 1)"
            exit 1
            ;;
    esac
done

PHASES=(
    "01-factory-reset.sh:Phase 1 - Factory Reset"
    "02-wrap-key.sh:Phase 2 - Shared Wrap Key"
    "03-auth-keys.sh:Phase 3 - Auth Keys"
    "04-import-keys.sh:Phase 4 - Import Keys to HSM-1"
    "05-generate-codesign.sh:Phase 5 - Generate Code Signing Key"
    "06-export.sh:Phase 6 - Export Objects"
    "07-import-backup.sh:Phase 7 - Import to Backup Devices"
    "08-verify.sh:Phase 8 - Verify All Devices"
    "09-cleanup.sh:Phase 9 - Cleanup"
)

echo "============================================"
echo "  YubiHSM 2 Three-Device Provisioning"
echo "============================================"
echo
echo "This will provision 3 YubiHSM 2 devices for VyOS"
echo "Secureboot and code signing operations."
echo
echo "Phases to run: $START_PHASE through 9"
echo

for i in "${!PHASES[@]}"; do
    phase_num=$((i + 1))
    IFS=':' read -r script desc <<< "${PHASES[$i]}"

    if [[ $phase_num -lt $START_PHASE ]]; then
        echo "SKIP: $desc (--from $START_PHASE)"
        continue
    fi

    echo
    echo ">>> Starting: $desc"
    echo

    bash "$SCRIPT_DIR/$script"

    echo
    echo ">>> Completed: $desc"

    # Pause between phases for user review (except after last phase)
    if [[ $phase_num -lt 9 ]]; then
        echo
        read -rp "Press Enter to continue to next phase, or Ctrl+C to stop... "
    fi
done

echo
echo "============================================"
echo "  Provisioning Complete"
echo "============================================"
echo
echo "All 3 devices are provisioned and verified."
echo "See docs/superpowers/specs/2026-03-30-yubihsm2-3device-setup-design.md"
echo "for the full specification."
