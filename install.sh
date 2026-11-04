#!/bin/zsh
# Builds a Release copy and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
xcodebuild -project Bower.xcodeproj -scheme Bower -configuration Release \
  -derivedDataPath build -quiet build

pkill -x Bower || true
# Let the old copy finish quitting (it puts parked windows back) before replacing it, or the launch below can fail.
for _ in {1..50}; do pgrep -x Bower >/dev/null || break; sleep 0.1; done
rm -rf /Applications/Bower.app
ditto build/Build/Products/Release/Bower.app /Applications/Bower.app
open /Applications/Bower.app || true
# Right after the copy, Launch Services sometimes doesn't start it; try again until it's running.
for _ in 1 2 3 4 5; do
  sleep 1
  pgrep -x Bower >/dev/null && break
  open /Applications/Bower.app || true
done
pgrep -x Bower >/dev/null || { echo "Bower didn't start; open /Applications/Bower.app by hand." >&2; exit 1; }
echo "Installed. Press ⌥1 / ⌥2 to switch layouts, middle-click for the Snap Wheel."
