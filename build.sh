#!/bin/zsh
# Builds CmdTab into ./build/CmdTab.app
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f CmdTab/Resources/AppIcon.icns ]; then
  swift scripts/make-icon.swift CmdTab/Resources/AppIcon.iconset
  iconutil -c icns CmdTab/Resources/AppIcon.iconset -o CmdTab/Resources/AppIcon.icns
fi
xcodegen generate --quiet
xcodebuild -project CmdTab.xcodeproj -scheme CmdTab -configuration "${1:-Release}" \
  -derivedDataPath build/DerivedData CONFIGURATION_BUILD_DIR="$PWD/build" build | grep -E "error|warning: unre|BUILD" || true
echo "App: $PWD/build/CmdTab.app"
