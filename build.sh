#!/bin/bash
set -euo pipefail

# Build OpenSwitch and assemble a runnable .app bundle.
# Requires only the Swift toolchain (Command Line Tools) — no full Xcode.

cd "$(dirname "$0")"

APP_NAME="OpenSwitch"
BUILD_CONFIG="release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"

echo "==> Building (${BUILD_CONFIG})..."
swift build -c "${BUILD_CONFIG}"

BIN_PATH="$(swift build -c "${BUILD_CONFIG}" --show-bin-path)/${APP_NAME}"

echo "==> Assembling ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"

cp "${BIN_PATH}" "${CONTENTS}/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${CONTENTS}/Info.plist"

echo "==> Ad-hoc code signing (stable identity for TCC/Automation)..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Done: ${APP_BUNDLE}"
echo "    Run with: open ./${APP_BUNDLE}"
