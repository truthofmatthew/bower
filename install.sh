#!/bin/zsh
# Builds a Release copy and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
xcodebuild -project Bower.xcodeproj -scheme Bower -configuration Release \
  -derivedDataPath build -quiet build

pkill -x Bower || true
rm -rf /Applications/Bower.app
ditto build/Build/Products/Release/Bower.app /Applications/Bower.app
open /Applications/Bower.app
echo "Installed. Press ⌥1 / ⌥2 to switch layouts, middle-click for the Snap Wheel."
