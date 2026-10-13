#!/usr/bin/env bash
#
# distribute-testflight.sh — AuGenda TestFlight Packaging & Distribution Script
# Conforms to EnsDev Apple Platform Standard v1.0
#

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_PATH="${PROJECT_DIR}/build/AuGenda.xcarchive"
EXPORT_PATH="${PROJECT_DIR}/build/TestFlight"
EXPORT_OPTIONS="${PROJECT_DIR}/ExportOptions-TestFlight.plist"

echo "=== AuGenda TestFlight Packaging ==="
echo "Project Directory: ${PROJECT_DIR}"

# 1. Check for Xcode toolchain
if ! xcode-select -p | grep -q "Xcode.app"; then
    echo "Notice: Active developer directory is $(xcode-select -p)."
    echo "Building archives for TestFlight distribution requires Xcode.app."
    echo "If Xcode is installed, run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo ""
    echo "Alternative: Push this repository branch to trigger Xcode Cloud or GitHub Actions,"
    echo "which will automatically archive and submit to TestFlight using cloud provisioning."
fi

# 2. Archive if xcodebuild is functional
if command -v xcodebuild >/dev/null 2>&1 && xcode-select -p | grep -q "Xcode.app"; then
    echo "Cleaning build directory..."
    rm -rf "${PROJECT_DIR}/build"
    mkdir -p "${PROJECT_DIR}/build"

    echo "Archiving AuGenda for Release..."
    xcodebuild archive \
        -project "${PROJECT_DIR}/AuGenda.xcodeproj" \
        -scheme "AuGenda" \
        -configuration Release \
        -destination "generic/platform=iOS" \
        -archivePath "${ARCHIVE_PATH}"

    echo "Exporting for TestFlight..."
    xcodebuild -exportArchive \
        -archivePath "${ARCHIVE_PATH}" \
        -exportPath "${EXPORT_PATH}" \
        -exportOptionsPlist "${EXPORT_OPTIONS}" \
        -allowProvisioningUpdates

    echo "=== Packaging Complete ==="
    echo "Exported package located at: ${EXPORT_PATH}"
fi
